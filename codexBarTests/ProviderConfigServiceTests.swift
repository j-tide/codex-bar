import XCTest
@testable import codexAppBar

@MainActor
final class ProviderConfigServiceTests: XCTestCase {
    private var workDir: URL!
    private var configURL: URL!
    private var modelsURL: URL!
    private var storeURL: URL!
    private var service: CodexProviderConfigService!

    override func setUp() async throws {
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-provider-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        configURL = workDir.appendingPathComponent("config.toml")
        modelsURL = workDir.appendingPathComponent("models.json")
        storeURL = workDir.appendingPathComponent("provider_accounts.json")
        service = CodexProviderConfigService(configURL: configURL, modelsURL: modelsURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    private let sampleConfig = """
    service_tier = "default"
    model_reasoning_effort = "max"

    [mcp_servers.pencil]
    command = "pencil"

    [projects."/tmp/demo"]
    trust_level = "trusted"
    """

    private func activate(
        key: String = "ZAI", model: String = "glm-5.3",
        baseURL: String = "https://open.bigmodel.cn/api/v1",
        apiKey: String = "secret-key", wireAPI: String? = nil
    ) throws -> ProviderAccount {
        let account = ProviderAccount(
            name: "智谱 GLM", providerKey: key, baseURL: baseURL,
            apiKey: apiKey, model: model, wireAPI: wireAPI
        )
        try service.activate(account)
        return account
    }

    func testActivateWritesTopLevelKeysAndProviderSection() throws {
        try sampleConfig.write(to: configURL, atomically: true, encoding: .utf8)
        try activate()

        let text = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertEqual(CodexProviderConfigService.topLevelValue(for: "model_provider", in: text), "ZAI")
        XCTAssertEqual(CodexProviderConfigService.topLevelValue(for: "model", in: text), "glm-5.3")
        XCTAssertEqual(
            CodexProviderConfigService.topLevelValue(for: "model_catalog_json", in: text),
            modelsURL.path
        )
        XCTAssertTrue(text.contains("[model_providers.ZAI]"))
        XCTAssertTrue(text.contains("base_url = \"https://open.bigmodel.cn/api/v1\""))
        XCTAssertTrue(text.contains("experimental_bearer_token = \"secret-key\""))
        XCTAssertTrue(text.contains("wire_api = \"responses\""))
        // 顶层键必须插在首个 section 之前，原有段落保持不动。
        let firstSection = try XCTUnwrap(text.range(of: "\n[mcp_servers.pencil]"))
        let topLevel = String(text[..<firstSection.lowerBound])
        XCTAssertTrue(topLevel.contains("model_provider = \"ZAI\""))
        XCTAssertTrue(text.contains("[mcp_servers.pencil]"))
        XCTAssertTrue(text.contains("trust_level = \"trusted\""))
        XCTAssertEqual(try permissions(of: configURL), 0o600)
        let backups = try FileManager.default.contentsOfDirectory(at: workDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("config.toml.bak-codexbar-provider-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try permissions(of: XCTUnwrap(backups.first)), 0o600)
    }

    func testActivateWritesCatalogForResponses() throws {
        try sampleConfig.write(to: configURL, atomically: true, encoding: .utf8)
        try activate()
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: modelsURL)) as? [String: Any]
        let models = try XCTUnwrap(catalog?["models"] as? [[String: Any]])
        let slugs = models.compactMap { $0["slug"] as? String }
        XCTAssertEqual(Set(slugs), Set(CodexProviderConfigService.codingPlanModels))
    }

    func testChatProviderIsRejectedWithoutChangingConfig() throws {
        try sampleConfig.write(to: configURL, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try activate(key: "DeepSeek", model: "deepseek-chat",
                                          baseURL: "https://api.deepseek.com/v1", wireAPI: "chat"))
        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), sampleConfig)
        XCTAssertFalse(FileManager.default.fileExists(atPath: modelsURL.path))
    }

    func testActivateKeepsOtherProviderSectionsAndReplacesOnlyTheSelectedOne() throws {
        try sampleConfig.write(to: configURL, atomically: true, encoding: .utf8)
        try activate()
        try activate(key: "Other", model: "other-model",
                     baseURL: "https://other.example/v1")
        try activate(key: "Other", model: "other-model-2",
                     baseURL: "https://other.example/v1")

        let text = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertEqual(text.components(separatedBy: "[model_providers.").count - 1, 2)
        XCTAssertTrue(text.contains("[model_providers.ZAI]"))
        XCTAssertEqual(text.components(separatedBy: "[model_providers.Other]").count - 1, 1)
        XCTAssertEqual(text.components(separatedBy: "model_provider =").count - 1, 1)
        XCTAssertEqual(text.components(separatedBy: "\nmodel =").count - 1, 1)
    }

    func testDeactivateRemovesOverrideAndRestoresOfficialModel() throws {
        try sampleConfig.write(to: configURL, atomically: true, encoding: .utf8)
        try activate()
        try service.deactivate(restoreModel: "gpt-5.5")

        let text = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertNil(CodexProviderConfigService.topLevelValue(for: "model_provider", in: text))
        XCTAssertNil(CodexProviderConfigService.topLevelValue(for: "model_catalog_json", in: text))
        XCTAssertEqual(CodexProviderConfigService.topLevelValue(for: "model", in: text), "gpt-5.5")
        XCTAssertFalse(text.contains("[model_providers.ZAI]"))
        XCTAssertTrue(text.contains("[mcp_servers.pencil]"))
        XCTAssertTrue(text.contains("trust_level = \"trusted\""))
    }

    func testDeactivateLeavesUnrelatedConfigUntouched() throws {
        try sampleConfig.write(to: configURL, atomically: true, encoding: .utf8)
        try service.deactivate(restoreModel: nil)
        let text = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertEqual(text, sampleConfig)
    }

    func testTopLevelValueParsing() {
        let text = """
        # model = "commented"
        model = "glm-5.3"
        modelx = "not-model"
        model_provider="ZAI"

        [section]
        model = "not-top-level"
        """
        XCTAssertEqual(CodexProviderConfigService.topLevelValue(for: "model", in: text), "glm-5.3")
        XCTAssertEqual(CodexProviderConfigService.topLevelValue(for: "model_provider", in: text), "ZAI")
        XCTAssertNil(CodexProviderConfigService.topLevelValue(for: "missing", in: text))
    }

    func testQuotedConfigValuesEscapeControlCharacters() {
        XCTAssertEqual(CodexProviderConfigService.quoted("a\"b\\c\nd\re\tf"), "\"a\\\"b\\\\c\\nd\\re\\tf\"")
    }

    func testRemoveSectionDropsSubsections() {
        let text = """
        keep = 1

        [provider.ZAI]
        a = 1

        [provider.ZAI.auth]
        b = 2

        [other]
        c = 3
        """
        let cleaned = CodexProviderConfigService.removeSection(named: "provider.ZAI", from: text)
        XCTAssertFalse(cleaned.contains("a = 1"))
        XCTAssertFalse(cleaned.contains("b = 2"))
        XCTAssertTrue(cleaned.contains("[other]"))
        XCTAssertTrue(cleaned.contains("keep = 1"))
    }

    func testSanitizedProviderKey() {
        XCTAssertEqual(ProviderAccount.sanitizedProviderKey("ZAI"), "ZAI")
        XCTAssertEqual(ProviderAccount.sanitizedProviderKey("my provider"), "myprovider")
        XCTAssertEqual(ProviderAccount.sanitizedProviderKey("--we--ird--"), "we--ird")
        XCTAssertEqual(ProviderAccount.sanitizedProviderKey("智谱"), "ZAI")
        XCTAssertEqual(ProviderAccount(name: "x", providerKey: "智谱", baseURL: "u", apiKey: "k", model: "m").providerKey, "ZAI")
        XCTAssertTrue(ProviderAccount.isValidProviderKey("my-provider_2"))
        XCTAssertFalse(ProviderAccount.isValidProviderKey("openai"))
        XCTAssertFalse(ProviderAccount.isValidProviderKey("bad key"))
        XCTAssertFalse(ProviderAccount.isValidProviderKey(""))
    }

    func testStoreUpsertMergesByProviderKeyAndPersists() throws {
        let store = ProviderAccountStore(
            storeURL: storeURL,
            configService: CodexProviderConfigService(configURL: configURL, modelsURL: modelsURL)
        )
        let first = store.upsert(ProviderAccount(
            name: "A", providerKey: "ZAI", baseURL: "https://a", apiKey: "k1", model: "glm-5.3"
        ))
        let second = store.upsert(ProviderAccount(
            name: "B", providerKey: "ZAI", baseURL: "https://b", apiKey: "k2", model: "glm-5.3-flash"
        ))
        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(store.accounts[0].baseURL, "https://b")

        // 重新加载同一存储文件，账号与官方 model 备份都应还原。
        let reloaded = ProviderAccountStore(
            storeURL: storeURL,
            configService: CodexProviderConfigService(configURL: configURL, modelsURL: modelsURL)
        )
        XCTAssertEqual(reloaded.accounts.count, 1)
        XCTAssertEqual(reloaded.accounts[0].name, "B")
    }

    func testDistinctCustomProviderIDsRemainSeparateAccounts() {
        let store = ProviderAccountStore(storeURL: storeURL, configService: service)
        store.upsert(ProviderAccount(name: "A", providerKey: "custom_a", baseURL: "https://a", apiKey: "k1", model: "a"))
        store.upsert(ProviderAccount(name: "B", providerKey: "custom_b", baseURL: "https://b", apiKey: "k2", model: "b"))
        XCTAssertEqual(store.accounts.map(\.providerKey), ["custom_a", "custom_b"])
    }

    func testStoreActivateTracksActiveKeyAndBacksUpOfficialModel() throws {
        try sampleConfig.write(to: configURL, atomically: true, encoding: .utf8)
        let store = ProviderAccountStore(
            storeURL: storeURL,
            configService: CodexProviderConfigService(configURL: configURL, modelsURL: modelsURL)
        )
        XCTAssertNil(store.activeProviderKey)

        let account = store.upsert(ProviderAccount(
            name: "智谱 GLM", providerKey: "ZAI",
            baseURL: "https://open.bigmodel.cn/api/v1", apiKey: "k", model: "glm-5.3"
        ))
        try store.activate(account)
        XCTAssertEqual(store.activeProviderKey, "ZAI")
        XCTAssertEqual(store.activeAccount?.id, account.id)
        XCTAssertNil(store.officialModelBackup)

        try store.deactivateProvider()
        XCTAssertNil(store.activeProviderKey)
        XCTAssertNil(store.officialModelBackup)
        let text = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertNil(CodexProviderConfigService.topLevelValue(for: "model_provider", in: text))
        XCTAssertNil(CodexProviderConfigService.topLevelValue(for: "model", in: text))
    }

    func testStoreFilePermissionsArePrivateAndExistingFileIsHardenedOnLoad() throws {
        let store = ProviderAccountStore(storeURL: storeURL, configService: service)
        store.upsert(ProviderAccount(name: "A", baseURL: "https://a", apiKey: "secret", model: "glm-5.3"))
        XCTAssertEqual(try permissions(of: storeURL), 0o600)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: storeURL.path)
        let reloaded = ProviderAccountStore(storeURL: storeURL, configService: service)
        XCTAssertEqual(reloaded.accounts.count, 1)
        XCTAssertEqual(try permissions(of: storeURL), 0o600)
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    func testMaskedKeyHidesMiddleSegment() {
        let account = ProviderAccount(
            name: "x", baseURL: "u", apiKey: "ba5af15708994d29a98be0ec06c9e395", model: "m"
        )
        XCTAssertTrue(account.maskedKey.hasPrefix("ba5a"))
        XCTAssertTrue(account.maskedKey.hasSuffix("e395"))
        XCTAssertTrue(account.maskedKey.contains("…"))
        XCTAssertEqual(ProviderAccount(name: "x", baseURL: "u", apiKey: "short", model: "m").maskedKey, "•••••")
    }
}
