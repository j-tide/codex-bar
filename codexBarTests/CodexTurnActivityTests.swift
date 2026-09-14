import XCTest
@testable import codexAppBar

@MainActor
final class CodexTurnActivityTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_789_389_682.592)

    private func event(_ kind: String, turn: String = "continued", date: String = "2026-09-14T12:41:22.592Z") -> String {
        "{\"timestamp\":\"\(date)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"\(kind)\",\"turn_id\":\"\(turn)\"}}\n"
    }

    private func hook(state: TaskActivityState = .ready, age: Double = 0.026,
                      source: String = "Stop") -> TaskActivityRecord {
        TaskActivityRecord(taskKey: "task", eventKey: "old-stop", state: state,
            phase: .waitingInput, projectName: "project", updatedAt: start.addingTimeInterval(-age), source: source)
    }

    func testGoalContinuationRestoresReadTaskAndRunningIndicator() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let readState = TaskReadState(defaults: defaults)
        let old = hook()
        XCTAssertTrue(readState.visibleRecords(from: [old], codexUnreadTaskKeys: []).isEmpty)
        let continued = CodexTurnActivity(turnID: "continued", startedAt: start).reconciling(old)
        let visible = readState.visibleRecords(from: [continued], codexUnreadTaskKeys: [])
        let snapshot = TaskCenterSnapshot(records: visible, now: start)
        XCTAssertEqual(snapshot.aggregateLight, .running)
        XCTAssertEqual(snapshot.runningCount, 1)
        XCTAssertNotEqual(continued.turnKey, old.turnKey)
    }

    func testNewerHooksRetainCompactionAndInterruptionAndCompletion() {
        let activity = CodexTurnActivity(turnID: "continued", startedAt: start)
        for source in ["Stop", "Interrupt", "PreCompact", "PermissionRequest"] {
            let newer = hook(state: source == "PermissionRequest" ? .needsAttention : .ready,
                             age: -1, source: source)
            XCTAssertEqual(activity.reconciling(newer), newer)
        }
    }

    func testCompletedContinuationDoesNotRemainRunning() {
        let ended = CodexTurnActivity(turnID: "continued", startedAt: start,
                                      endedAt: start.addingTimeInterval(10)).reconciling(hook())
        XCTAssertEqual(ended.state, .ready)
        XCTAssertEqual(TaskCenterSnapshot(records: [ended], now: start).runningCount, 0)
    }

    func testInitialScanCrossesLargeToolOutputAndIncrementallyHandlesPartialEvents() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let tool = "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"text\":\"" + String(repeating: "x", count: 300_000) + "\"}}\n"
        try (event("task_complete", turn: "old") + event("task_started") + tool + tool).write(to: url, atomically: true, encoding: .utf8)
        let reader = CodexTurnActivityReader()
        let first = await reader.read(path: url.path)
        XCTAssertEqual(first?.turnID, "continued")
        XCTAssertNil(first?.endedAt)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        // A delayed completion from the previous turn must not end this one.
        try handle.write(contentsOf: Data(event("task_complete", turn: "old").utf8))
        let unrelated = await reader.read(path: url.path)
        XCTAssertNil(unrelated?.endedAt)
        let completion = event("task_complete", date: "2026-09-14T12:42:22.592Z")
        try handle.write(contentsOf: Data(completion.dropLast(2).utf8))
        let partial = await reader.read(path: url.path)
        XCTAssertNil(partial?.endedAt)
        try handle.write(contentsOf: Data(completion.suffix(2).utf8))
        let ended = await reader.read(path: url.path)
        XCTAssertEqual(ended?.endedAt, start.addingTimeInterval(60))
        let cached = await reader.read(path: url.path)
        XCTAssertEqual(cached, ended)
        let freshReader = CodexTurnActivityReader()
        let cold = await freshReader.read(path: url.path)
        XCTAssertEqual(cold, ended)
    }

    func testReplacementTruncationAndMissingSourceDiscardCachedActivity() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = CodexTurnActivityReader()
        try event("task_started").write(to: url, atomically: true, encoding: .utf8)
        let first = await reader.read(path: url.path)
        XCTAssertNotNil(first)
        try (event("task_started", turn: "replacement") + event("turn_aborted", turn: "replacement"))
            .write(to: url, atomically: true, encoding: .utf8)
        let replaced = await reader.read(path: url.path)
        XCTAssertEqual(replaced?.turnID, "replacement")
        XCTAssertNotNil(replaced?.endedAt)
        try Data().write(to: url)
        let truncated = await reader.read(path: url.path)
        XCTAssertNil(truncated)
        try FileManager.default.removeItem(at: url)
        let missing = await reader.read(path: url.path)
        XCTAssertNil(missing)
    }
}
