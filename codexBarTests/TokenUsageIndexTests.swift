import Foundation
import XCTest
@testable import codexAppBar

@MainActor
final class TokenUsageIndexTests: XCTestCase {
    func testCachedCalendarWindowsKeepUniqueThreadCountsAcrossDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let snapshot = CodexStatsDB.Snapshot(
            stat: .init(threadCount: 1, totalTokens: 30),
            dailyTokens: ["2026-08-31": 1000, "2026-09-01": 100, "2026-09-07": 20, "2026-09-12": 30],
            dailyThreads: ["2026-08-31": ["old"], "2026-09-01": ["a"], "2026-09-07": ["a", "b"], "2026-09-12": ["b"]])
        let today = try Date("2026-09-11T16:00:00Z", strategy: .iso8601)
        let week = try Date("2026-09-06T16:00:00Z", strategy: .iso8601)
        let month = try Date("2026-08-31T16:00:00Z", strategy: .iso8601)
        XCTAssertEqual(snapshot.windowStat(since: today, calendar: calendar), .init(threadCount: 1, totalTokens: 30))
        XCTAssertEqual(snapshot.windowStat(since: week, calendar: calendar), .init(threadCount: 2, totalTokens: 50))
        XCTAssertEqual(snapshot.windowStat(since: month, calendar: calendar), .init(threadCount: 2, totalTokens: 150))
        XCTAssertEqual(snapshot.windowStat(since: today.addingTimeInterval(86400), calendar: calendar), .init())
    }

    private func event(_ timestamp: String, total: Int, last: Int) -> Data {
        Data("{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":\(total)},\"last_token_usage\":{\"total_tokens\":\(last)}}}}\n".utf8)
    }

    func testInheritedCountersDuplicatesAndResetsOnlyCountNewUsage() {
        var parser = CodexTokenUsageParser()
        XCTAssertEqual(parser.consume(event("2026-09-11T15:59:00.000Z", total: 1_000_000, last: 80))?.tokens, 80)
        XCTAssertEqual(parser.consume(event("2026-09-11T16:00:00.000Z", total: 1_000_120, last: 120))?.tokens, 120)
        XCTAssertNil(parser.consume(event("2026-09-11T16:00:01Z", total: 1_000_120, last: 120)))
        XCTAssertEqual(parser.consume(event("2026-09-11T16:01:00Z", total: 25, last: 25))?.tokens, 25)
        XCTAssertEqual(parser.consume(event("2026-09-11T16:02:00Z", total: 40, last: 15))?.tokens, 15)
    }

    func testLocalMidnightCopiesPartialWritesAndPersistedIncrementalCache() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("session.jsonl")
        let copy = root.appendingPathComponent("copy.jsonl")
        let cache = root.appendingPathComponent("cache.json")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let today = try Date("2026-09-11T16:00:00Z", strategy: .iso8601)
        let now = today.addingTimeInterval(3600)
        let yesterday = today.addingTimeInterval(-86400)
        let meta = Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"thread-a\"}}\n".utf8)
        let old = event("2026-09-11T15:59:00Z", total: 1000, last: 1000)
        let new = event("2026-09-11T16:01:00Z", total: 1100, last: 100)
        let tail = event("2026-09-11T16:02:00Z", total: 1150, last: 50)
        try (meta + old + new + tail.prefix(tail.count / 2)).write(to: file)
        try (meta + old + new).write(to: copy)
        func read(_ index: CodexTokenUsageIndex) throws -> CodexStatsDB.Snapshot {
            try XCTUnwrap(index.snapshot(roots: [root], statSince: today, dailySince: yesterday, now: now, calendar: calendar))
        }
        let index = CodexTokenUsageIndex(cacheURL: cache)
        let first = try read(index)
        XCTAssertEqual(first.stat.totalTokens, 100)
        XCTAssertEqual(first.stat.threadCount, 1)
        XCTAssertEqual(first.dailyTokens, ["2026-09-11": 1000, "2026-09-12": 100])
        let writer = try FileHandle(forWritingTo: file)
        try writer.seekToEnd()
        try writer.write(contentsOf: tail.suffix(tail.count - tail.count / 2))
        try writer.close()
        let second = try read(index)
        XCTAssertEqual(second.stat.totalTokens, 150)
        XCTAssertEqual(try read(index).stat.totalTokens, 150)
        XCTAssertEqual(try read(CodexTokenUsageIndex(cacheURL: cache)).stat.totalTokens, 150)
        // A future event is not charged to today, and copied archives are not double-counted.
        let future = event("2026-09-12T16:00:00Z", total: 1300, last: 150)
        let append = try FileHandle(forWritingTo: file)
        try append.seekToEnd(); try append.write(contentsOf: future); try append.close()
        XCTAssertEqual(try read(index).stat.totalTokens, 150)
        // Truncated/rotated logs reset the cached baseline rather than reusing stale totals.
        try (meta + event("2026-09-11T16:03:00Z", total: 9000, last: 30)).write(to: file)
        XCTAssertEqual(try read(index).stat.totalTokens, 130)
    }
}
