import Foundation
import XCTest
@testable import codexAppBar

@MainActor
final class CodexReadStateTests: XCTestCase {
    private let thread = "00000000-0000-4000-8000-000000000001"
    private let otherThread = "00000000-0000-4000-8000-000000000002"
    private let host = "local:092af2cb59bdd804c6f7f1cd1d85464b682974e43cd517397d25510024034d1c"

    private func auth(_ account: String = "account") throws -> Data {
        let payload = try JSONSerialization.data(withJSONObject: ["https://api.openai.com/auth": [
            "chatgpt_account_id": account, "user_id": "user", "chatgpt_user_id": "wrong-fallback"
        ]]).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return try JSONSerialization.data(withJSONObject: ["tokens": ["access_token": "header.\(payload).signature"]])
    }

    private func state(_ ids: [String], identity: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["electron-thread-read-state-v1": [
            "version": 1,
            "unreadByIdentity": [identity: [host: ids, "ssh:another-host": [otherThread]],
                                 "old-account": [host: [otherThread]]],
            "legacyMigration": ["unreadThreadIdsByHostId": ["local": [otherThread]]]
        ]])
    }

    func testIdentityAndLocalHostScopeMatchCodexWithoutMergingLegacyOrOtherAccounts() throws {
        let identity = try XCTUnwrap(CodexReadStateReader.identityKey(authData: auth()))
        XCTAssertEqual(identity, CodexReadStateReader.hash(Data("[\"chatgpt\",\"account\",\"user\"]".utf8)))
        let snapshot = try XCTUnwrap(CodexReadStateReader.snapshot(stateData: state([thread], identity: identity), identityKey: identity))
        XCTAssertEqual(snapshot.unreadTaskKeys, [CodexTaskMetadata.taskKey(for: thread)])
        XCTAssertEqual(CodexReadStateReader.snapshot(stateData: try state([], identity: identity), identityKey: identity)?.unreadTaskKeys, [])
        XCTAssertEqual(CodexReadStateReader.snapshot(stateData: try state([thread], identity: identity), identityKey: "new-account")?.unreadTaskKeys, [])
    }

    func testMissingMalformedOrUnsupportedStateIsNotAnEmptyReadSnapshot() throws {
        for data in [Data(), Data("{".utf8), Data("{}".utf8),
                     Data("{\"electron-thread-read-state-v1\":{\"version\":2,\"unreadByIdentity\":{}}}".utf8)] {
            XCTAssertNil(CodexReadStateReader.snapshot(stateData: data, identityKey: "account"))
        }
        XCTAssertNil(CodexReadStateReader.identityKey(authData: Data("{}".utf8)))
        XCTAssertNil(CodexReadStateReader.snapshot(stateData: try state(["not-a-thread"], identity: "account"), identityKey: "account"))
    }

    func testCodexReadStateControlsListCountsAndCompletionNotificationCandidates() throws {
        let suite = "codexbar.codex-read.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let reader = TaskReadState(defaults: defaults)
        let ready = TaskActivityRecord(taskKey: "ready", eventKey: "completed-turn", state: .ready,
            phase: .waitingInput, projectName: "project", updatedAt: Date(), source: "Stop")
        let running = TaskActivityRecord(taskKey: "running", eventKey: "started-turn", state: .running,
            phase: .processing, projectName: "project", updatedAt: Date(), source: "UserPromptSubmit")
        func visible(_ unread: Set<String>?) -> [TaskActivityRecord] {
            reader.visibleRecords(from: [ready, running], knownTaskKeys: ["ready", "running"],
                                  codexUnreadTaskKeys: unread, requiresCodexReadState: true)
        }
        XCTAssertEqual(visible(nil).map(\.taskKey), ["running"], "No inferred completions before the first desktop snapshot")
        XCTAssertEqual(TaskCenterSnapshot(records: visible(["ready"]), now: Date()).readyCount, 1,
                       "First launch must retain a completion Codex actually marks unread")
        reader.markRead(ready)
        XCTAssertEqual(visible(["ready"]).count, 2, "Opening via the app waits for Codex's acknowledgement")
        XCTAssertEqual(visible([]).map(\.taskKey), ["running"], "Reading in Codex removes the same notification candidate and row")
        XCTAssertEqual(visible(["ready"]).count, 2, "A later unread change must override old local acknowledgements")
    }

    func testMonitorTracksDesktopFileChangesWithoutHookEventsAndInvalidatesOnAccountChange() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-read-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let authURL = root.appendingPathComponent("auth.json")
        let stateURL = root.appendingPathComponent(".codex-global-state.json")
        let firstAuth = try auth()
        let identity = try XCTUnwrap(CodexReadStateReader.identityKey(authData: firstAuth))
        try firstAuth.write(to: authURL)
        try state([thread], identity: identity).write(to: stateURL)
        let monitor = CodexReadStateMonitor(directory: root)
        defer { monitor.stop() }
        var updates = 0
        monitor.start { updates += 1 }
        try await waitUntil { monitor.snapshot?.unreadTaskKeys == [CodexTaskMetadata.taskKey(for: self.thread)] }
        try state([], identity: identity).write(to: stateURL, options: .atomic)
        try await waitUntil { monitor.snapshot?.unreadTaskKeys == [] }
        try state([thread], identity: identity).write(to: stateURL, options: .atomic)
        try await waitUntil { monitor.snapshot?.unreadTaskKeys.count == 1 }
        try Data("{".utf8).write(to: stateURL)
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(monitor.snapshot?.unreadTaskKeys.count, 1, "Partial writes retain the last good snapshot")
        try auth("other-account").write(to: authURL, options: .atomic)
        try await waitUntil { monitor.snapshot == nil }
        XCTAssertGreaterThanOrEqual(updates, 4)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<120 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Read-state monitor did not publish the change within three seconds")
    }
}
