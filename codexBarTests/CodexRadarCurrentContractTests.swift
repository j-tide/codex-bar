import Foundation
import XCTest
@testable import codexAppBar

@MainActor
final class CodexRadarCurrentContractTests: XCTestCase {
    func testServiceLoadsTheCurrentWebsiteRoundWithoutRequestingLegacyRadarBench() async throws {
        let results = try fixtureData("four-task-results")
        let session = makeSession()
        defer { session.invalidateAndCancel(); CurrentRadarURLProtocol.respond = nil }
        CurrentRadarURLProtocol.respond = { request in
            switch request.url?.path {
            case "/data/codex-four-task-results.json": return (200, results)
            case "/current.json": return (503, Data())
            default:
                XCTFail("Unexpected legacy or unrelated request: \(request.url?.absoluteString ?? "nil")")
                return (404, Data())
            }
        }
        let service = CodexRadarService(session: session)

        await service.refresh()

        XCTAssertNil(service.lastError)
        XCTAssertNil(service.snapshot, "Reset-window failure must not prevent scores loading")
        XCTAssertNotNil(service.lastFetchAt)
        let report = try XCTUnwrap(service.intelligence)
        XCTAssertEqual(report.selectionCount, 46)
        XCTAssertEqual(report.maximumScore, 150)
        XCTAssertFalse(report.sourceName.isEmpty)
        XCTAssertTrue(report.testWindow?.contains("2026-10-29") == true)
        XCTAssertFalse(report.isPartial)
        let matrix = CodexRadarPresentation.matrix(from: report.modelIQ)
        XCTAssertEqual(matrix.rows.count, 8)
        XCTAssertEqual(matrix.cells.count, 46)
        XCTAssertTrue(matrix.rows.contains { $0.displayName == "GPT-6.1 Terra" })
        XCTAssertTrue(matrix.rows.contains { $0.displayName == "GPT-5.6 Terra" })
        XCTAssertEqual(try score(report, model: "gpt-6.1-sol", effort: "high"), 123.80192307692307, accuracy: 0.0000000001)
    }

    func testEveryCurrentRoundScoreMatchesTheWebsiteProjection() throws {
        let report = try CodexRadarFourTaskResults.decode(fixtureData("four-task-results")).report
        let expected = try fixtureObject("four-task-expected-scores")
        let rows = try XCTUnwrap(expected["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 46)
        for row in rows {
            let model = try XCTUnwrap(row["model"] as? String)
            let effort = try XCTUnwrap(row["effort"] as? String)
            let expectedScore = try XCTUnwrap(row["score150"] as? Double)
            XCTAssertEqual(try score(report, model: model, effort: effort), expectedScore, accuracy: 0.0000000001,
                           "Website score mismatch for \(model) / \(effort)")
            let display = try XCTUnwrap(row["score150_display"] as? String)
            XCTAssertEqual(MetricFormat.score.text(try score(report, model: model, effort: effort)), display,
                           "Website display mismatch for \(model) / \(effort)")
        }
    }

    func testServiceKeepsLastGoodRoundDuringFailureAndRecoversOnTheNextRefresh() async throws {
        let results = try fixtureData("four-task-results")
        let session = makeSession()
        defer { session.invalidateAndCancel(); CurrentRadarURLProtocol.respond = nil }
        CurrentRadarURLProtocol.respond = { request in
            request.url?.path == "/data/codex-four-task-results.json" ? (200, results) : (503, Data())
        }
        let service = CodexRadarService(session: session)
        await service.refresh()
        let original = try XCTUnwrap(service.intelligence)
        let fetchedAt = try XCTUnwrap(service.lastFetchAt)
        let originalScore = try score(original, model: "gpt-6.1-sol", effort: "high")

        CurrentRadarURLProtocol.respond = { _ in (503, Data()) }
        await service.refresh()

        XCTAssertTrue(service.lastError?.contains("503") == true)
        XCTAssertEqual(service.lastFetchAt, fetchedAt)
        XCTAssertEqual(service.intelligence?.selectionCount, 46)
        XCTAssertEqual(try score(XCTUnwrap(service.intelligence), model: "gpt-6.1-sol", effort: "high"), originalScore)
        XCTAssertFalse(service.isRefreshing)

        var updated = try fixtureObject("four-task-results")
        var rows = try XCTUnwrap(updated["rows"] as? [[String: Any]])
        let highIndex = try XCTUnwrap(rows.firstIndex { ($0["model"] as? String) == "gpt-6.1-sol" && ($0["effort"] as? String) == "high" })
        rows[highIndex]["combined"] = ["score": 0]
        updated["rows"] = rows
        updated["round_id"] = "next-author-round"
        let updatedData = try JSONSerialization.data(withJSONObject: updated)
        CurrentRadarURLProtocol.respond = { request in
            request.url?.path == "/data/codex-four-task-results.json" ? (200, updatedData) : (503, Data())
        }
        await service.refresh()

        XCTAssertNil(service.lastError)
        let recovered = try XCTUnwrap(service.intelligence)
        XCTAssertFalse(recovered.isPartial)
        XCTAssertEqual(recovered.selectionCount, 46)
        XCTAssertEqual(try score(recovered, model: "gpt-6.1-sol", effort: "high"), originalScore - 41.4, accuracy: 0.0000000001)
        XCTAssertFalse(service.isRefreshing)
    }

    func testMissingTaskOrRowRetainsCatalogWithoutInventingAZeroScore() throws {
        let original = try fixtureObject("four-task-results")
        for omitWholeRow in [false, true] {
            var payload = original
            var rows = try XCTUnwrap(payload["rows"] as? [[String: Any]])
            if omitWholeRow { rows.removeFirst() }
            else { rows[0]["pompeii"] = NSNull() }
            payload["rows"] = rows
            let report = try CodexRadarFourTaskResults.decode(JSONSerialization.data(withJSONObject: payload)).report
            XCTAssertEqual(report.selectionCount, 46)
            XCTAssertTrue(report.isPartial)
            let matrix = CodexRadarPresentation.matrix(from: report.modelIQ)
            XCTAssertEqual(matrix.rows.count, 8)
            XCTAssertEqual(matrix.cells.count, 45)
            let sol = try XCTUnwrap(matrix.rows.first { $0.displayName == "GPT-6.1 Sol" })
            XCTAssertNil(sol.cell(for: "low"))
        }
        var allMissing = original
        allMissing["rows"] = []
        let emptyReport = try CodexRadarFourTaskResults.decode(JSONSerialization.data(withJSONObject: allMissing)).report
        XCTAssertEqual(emptyReport.selectionCount, 46)
        XCTAssertTrue(emptyReport.isPartial)
        XCTAssertEqual(CodexRadarPresentation.matrix(from: emptyReport.modelIQ).rows.count, 8)
        XCTAssertTrue(CodexRadarPresentation.matrix(from: emptyReport.modelIQ).cells.isEmpty)
    }

    func testCurrentRoundPreservesARealZeroScore() throws {
        var payload = try fixtureObject("four-task-results")
        var rows = try XCTUnwrap(payload["rows"] as? [[String: Any]])
        rows[0]["combined"] = ["score": 0]
        rows[0]["pompeii"] = ["reward": 0]
        rows[0]["pelican"] = ["score": 0]
        rows[0]["candy"] = ["correct": false]
        payload["rows"] = rows
        let report = try CodexRadarFourTaskResults.decode(JSONSerialization.data(withJSONObject: payload)).report
        XCTAssertEqual(try score(report, model: "gpt-6.1-sol", effort: "low"), 0)
        XCTAssertFalse(report.isPartial)
    }

    func testCurrentRoundRejectsUnknownContractsInvalidScoresAndConflictingIdentities() throws {
        let valid = try fixtureObject("four-task-results")
        for (key, value) in [
            ("schema", "unknown-schema" as Any),
            ("protocol", "unknown-weighting" as Any),
            ("score_max", 100 as Any),
            ("task_weights", ["combined": 60, "pompeii": 45, "pelican": 22.5, "candy": 1] as Any)
        ] {
            var invalid = valid
            invalid[key] = value
            XCTAssertThrowsError(try CodexRadarFourTaskResults.decode(JSONSerialization.data(withJSONObject: invalid)), key)
        }
        let validRows = try XCTUnwrap(valid["rows"] as? [[String: Any]])
        let invalidRowValues: [(String, Any)] = [
            ("model", "outside-the-catalog"), ("effort", "outside-the-catalog"),
            ("combined", ["score": -1]), ("combined", ["score": 100.001]),
            ("pompeii", ["reward": -0.001]), ("pompeii", ["reward": 1.001]),
            ("pelican", ["score": 100.001]), ("candy", ["correct": "true"])
        ]
        for (key, value) in invalidRowValues {
            var invalid = valid
            var rows = validRows
            rows[0][key] = value
            invalid["rows"] = rows
            XCTAssertThrowsError(try CodexRadarFourTaskResults.decode(JSONSerialization.data(withJSONObject: invalid)), "Invalid \(key): \(value)")
        }
        var duplicate = valid
        duplicate["rows"] = validRows + [validRows[0]]
        XCTAssertThrowsError(try CodexRadarFourTaskResults.decode(JSONSerialization.data(withJSONObject: duplicate)))
    }

    func testDecoderPreservesRaw150PointScoresAndLegacy100PointFixtures() throws {
        let binding = try CodexRadarBenchBinding.decode(fixtureData("bench-binding-150"))
        let selection = CodexRadarSelection(model: "gpt-6.1-sol", effort: "high")
        let captured = try fixtureObject("bench-summary-150")
        let cases: [(score: Double?, coverage: Int, status: String)] = [
            (97.90210570679321, 64, "complete"),
            (127.54592282717283, 64, "complete"),
            (150, 64, "complete"),
            (0, 1, "provisional"),
            (nil, 0, "missing_current_result")
        ]
        for value in cases {
            var payload = captured
            payload["score"] = value.score.map { $0 as Any } ?? NSNull()
            payload["coverage"] = value.coverage
            payload["score_status"] = value.status
            let summary = try CodexRadarBenchSummary.decode(
                JSONSerialization.data(withJSONObject: payload), binding: binding, selection: selection
            )
            XCTAssertEqual(summary.score, value.score, "Scores must retain the server's native scale")
            XCTAssertEqual(summary.coverage, value.coverage)
        }
        for schema in [
            "radar-bench-public-summary-v3-150",
            "radar-bench-public-summary-v4-150-daily",
            "radar-bench-public-summary-v5-150-daily-graded-count",
            "radar-bench-public-summary-v6-150-details"
        ] {
            var payload = captured
            payload["schema"] = schema
            let summary = try CodexRadarBenchSummary.decode(
                JSONSerialization.data(withJSONObject: payload), binding: binding, selection: selection
            )
            XCTAssertEqual(summary.score, 97.90210570679321, schema)
        }

        let legacyBinding = try CodexRadarBenchBinding.decode(fixtureData("bench-binding"))
        let missing = try CodexRadarBenchSummary.decode(
            fixtureData("bench-summary"), binding: legacyBinding, selection: selection
        )
        XCTAssertNil(missing.score)
        let legacyPayloads = try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData("bench-public-summaries")) as? [[String: Any]])
        var scores: [String: Double] = [:]
        for payload in legacyPayloads {
            let legacySelection = CodexRadarSelection(
                model: try XCTUnwrap(payload["model"] as? String),
                effort: try XCTUnwrap(payload["effort"] as? String)
            )
            let summary = try CodexRadarBenchSummary.decode(
                JSONSerialization.data(withJSONObject: payload), binding: legacyBinding, selection: legacySelection
            )
            if legacySelection.model == "gpt-6.1-sol" { scores[legacySelection.effort] = summary.score }
        }
        XCTAssertEqual(scores["low"], 75)
        XCTAssertEqual(scores["xhigh"], 0)
        XCTAssertNil(scores["high"])
    }

    func test150PointContractRejectsLegacyMetadataMismatchedScalesAndInvalidScores() throws {
        let binding = try CodexRadarBenchBinding.decode(fixtureData("bench-binding-150"))
        let selection = CodexRadarSelection(model: "gpt-6.1-sol", effort: "high")
        let valid = try fixtureObject("bench-summary-150")
        let invalidValues: [(String, Any)] = [
            ("schema", "radar-bench-public-summary-v1"),
            ("schema", "radar-bench-public-summary-v99-150-details"),
            ("score_version", "radar-bench-v1"),
            ("score_version", "radar-bench-v3-150"),
            ("score_max", 100), ("score_max", 151), ("score_max", NSNull()),
            ("scoring_policy_version", "radar-bench-v1-last3-per-task-equal-weight-100"),
            ("scoring_policy_version", "unknown-policy"),
            ("score", -0.001), ("score", 150.001), ("score", NSNull())
        ]
        for (key, value) in invalidValues {
            var invalid = valid
            invalid[key] = value
            XCTAssertThrowsError(try CodexRadarBenchSummary.decode(
                JSONSerialization.data(withJSONObject: invalid), binding: binding, selection: selection
            ), "Invalid \(key): \(value)")
        }
        var missingScale = valid
        missingScale.removeValue(forKey: "score_max")
        XCTAssertThrowsError(try CodexRadarBenchSummary.decode(
            JSONSerialization.data(withJSONObject: missingScale), binding: binding, selection: selection
        ))
        XCTAssertThrowsError(try CodexRadarBenchSummary.decode(
            fixtureData("bench-summary"), binding: binding, selection: selection
        ))

        let validBinding = try fixtureObject("bench-binding-150")
        for (key, value) in [
            ("score_version", "radar-bench-v1" as Any),
            ("score_version", "unknown-version" as Any),
            ("score_version", NSNull() as Any),
            ("score_max", 100 as Any),
            ("score_max", NSNull() as Any)
        ] {
            var invalid = validBinding
            invalid[key] = value
            XCTAssertThrowsError(try CodexRadarBenchBinding.decode(
                JSONSerialization.data(withJSONObject: invalid)
            ), "Invalid binding \(key): \(value)")
        }
        for missingKey in ["score_version", "score_max"] {
            var invalid = validBinding
            invalid.removeValue(forKey: missingKey)
            XCTAssertThrowsError(try CodexRadarBenchBinding.decode(
                JSONSerialization.data(withJSONObject: invalid)
            ), "Incomplete binding scale: \(missingKey)")
        }
        let legacyBinding = try CodexRadarBenchBinding.decode(fixtureData("bench-binding"))
        XCTAssertThrowsError(try CodexRadarBenchSummary.decode(
            fixtureData("bench-summary-150"), binding: legacyBinding, selection: selection
        ))
    }

    private func fixtureData(_ name: String) throws -> Data {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return try Data(contentsOf: directory.appendingPathComponent("Fixtures/Radar/\(name).json"))
    }

    private func fixtureObject(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData(name)) as? [String: Any])
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CurrentRadarURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func score(_ report: CodexRadarIntelligenceReport, model: String, effort: String) throws -> Double {
        let selection = CodexRadarSelection(model: model, effort: effort)
        return try XCTUnwrap(report.modelIQ.comparisons[selection.key]?.latest?.score)
    }

}

private final class CurrentRadarURLProtocol: URLProtocol {
    nonisolated(unsafe) static var respond: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let respond = Self.respond, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, data) = try respond(request)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
