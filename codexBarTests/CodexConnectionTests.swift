import XCTest
import SQLite3
@testable import codexAppBar

final class CodexConnectionTests: XCTestCase {
    private var root: URL!
    private var codex: URL { root.appendingPathComponent("codex") }
    private var ccSwitch: URL { root.appendingPathComponent("cc-switch") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ccSwitch, withIntermediateDirectories: true)
        try write(#"{"auth_mode":"chatgpt","tokens":{"access_token":"fixture"}}"#, to: "auth.json")
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func write(_ text: String, to name: String) throws {
        try text.write(to: codex.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func configure(_ endpoint: String, provider: String = "custom") throws {
        try write("""
        model_provider = "\(provider)"
        [model_providers."\(provider)"]
        base_url = '\(endpoint)' # active endpoint
        requires_openai_auth = true
        """, to: "config.toml")
    }

    private func database() throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(ccSwitch.appendingPathComponent("cc-switch.db").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE proxy_config (app_type TEXT, listen_address TEXT, listen_port INTEGER);
        INSERT INTO proxy_config VALUES ('codex', '127.0.0.1', 15721);
        CREATE TABLE providers (id TEXT, app_type TEXT, name TEXT, settings_config TEXT, is_current INTEGER);
        INSERT INTO providers VALUES ('third-party', 'codex', 'Example Provider',
        '{"config":"model_provider = \\"custom\\"\\n[model_providers.custom]\\nbase_url = \\"https://provider.example/v1\\""}', 1);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }

    private func read() -> CodexConnectionStatus {
        CodexConnectionReader.read(codexDirectory: codex, ccSwitchDirectory: ccSwitch)
    }

    func testProxyEndpointTakesPrecedenceOverSubscriptionTokens() throws {
        try database()
        try configure("http://127.0.0.1:15721/v1")
        XCTAssertEqual(read().mode, .ccSwitchRouting)
        XCTAssertEqual(read().endpoint, "http://127.0.0.1:15721/v1")
    }

    func testDirectProviderMatchesActualEndpoint() throws {
        try database()
        try configure("https://provider.example/v1/")
        XCTAssertEqual(read().mode, .ccSwitchDirect)
        XCTAssertEqual(read().provider, "Example Provider")
    }

    func testSubscriptionDoesNotInheritStaleCCSwitchSelection() throws {
        try database()
        try write("model_provider = 'openai'", to: "config.toml")
        XCTAssertEqual(read().mode, .subscription)
    }

    func testUnrelatedLocalProxyIsNotCCSwitch() throws {
        try database()
        try configure("http://127.0.0.1:9999/v1")
        XCTAssertEqual(read().mode, .customAPI)
    }

    func testMissingConfigUsesDefaultProviderButUnreadableProviderDoesNot() throws {
        XCTAssertEqual(read().mode, .subscription)
        try write("model_provider = 'missing'", to: "config.toml")
        XCTAssertEqual(read().mode, .unknown)
    }

    func testAPIKeyIsNotASubscription() throws {
        try write(#"{"auth_mode":"apikey","OPENAI_API_KEY":"fixture"}"#, to: "auth.json")
        XCTAssertEqual(read().mode, .customAPI)
    }

    func testProfileOverridesRootAndIgnoresOtherTables() throws {
        try database()
        try write("""
        model_provider = 'openai'
        profile = 'work'
        [profiles.work]
        model_provider = 'custom'
        [model_providers.custom]
        base_url = "http://localhost:15721/v1" # proxy
        [projects."/some/path"]
        model_provider = 'unrelated'
        """, to: "config.toml")
        XCTAssertEqual(read().mode, .ccSwitchRouting)
    }

    func testReadingAgainObservesAtomicConfigurationSwitch() throws {
        try database()
        try configure("http://127.0.0.1:15721/v1")
        XCTAssertEqual(read().mode, .ccSwitchRouting)
        try configure("https://provider.example/v1")
        XCTAssertEqual(read().mode, .ccSwitchDirect)
        try write("", to: "config.toml")
        XCTAssertEqual(read().mode, .subscription)
    }

    func testEndpointDisplayDoesNotExposeCredentialsOrQuery() throws {
        try configure("https://user:secret@other.example/v1?api_key=secret#fragment")
        XCTAssertEqual(read().endpoint, "https://other.example/v1")
    }

    func testUnmanagedEndpointWithSubscriptionTokensRemainsCustomAPI() throws {
        try configure("https://other.example/v1")
        XCTAssertEqual(read().mode, .customAPI)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ccSwitch.appendingPathComponent("cc-switch.db").path))
    }

    func testQuotedAndDottedKeysStillSelectTheProxy() throws {
        try database()
        try write("""
        "model_provider" = 'custom'
        model_providers.custom.base_url = 'http://127.0.0.1:15721/v1'
        """, to: "config.toml")
        XCTAssertEqual(read().mode, .ccSwitchRouting)
    }

    func testMultilineInstructionsCannotChangeConnectionSelection() throws {
        let config = [
            "instructions = \"\"\"",
            "model_provider = 'fake'",
            "[model_providers.fake]",
            "base_url = 'https://fake.example'",
            "\"\"\"",
            "model_provider = 'openai'"
        ].joined(separator: "\n")
        try write(config, to: "config.toml")
        XCTAssertEqual(read().mode, .subscription)
    }

    func testMalformedConfigAndMissingAuthDoNotClaimSubscription() throws {
        try write("model_provider = \"unfinished", to: "config.toml")
        XCTAssertEqual(read().mode, .unknown)
        try write("", to: "config.toml")
        try FileManager.default.removeItem(at: codex.appendingPathComponent("auth.json"))
        XCTAssertEqual(read().mode, .unknown)
    }
}
