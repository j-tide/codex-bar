import Foundation
import XCTest
@testable import codexAppBar

@MainActor
final class CodexRadarCurrentContractTests: XCTestCase {
    func testServiceLoadsEverySelectedConfigurationFromThe150PointCatalog() async throws {
        let bindingData = try fixtureData("bench-binding-150")
        let binding = try CodexRadarBenchBinding.decode(bindingData)
        let session = makeSession()
        defer { session.invalidateAndCancel(); CurrentRadarURLProtocol.respond = nil }
        CurrentRadarURLProtocol.respond = try selectedSummaryResponse(bindingData: bindingData)
        let service = CodexRadarService(session: session)

        await service.refresh()

        XCTAssertNil(service.lastError)
        let report = try XCTUnwrap(service.intelligence)
        XCTAssertGreaterThanOrEqual(report.summaries.count, 34)
        XCTAssertEqual(report.summaries.count, binding.selections.count)
        XCTAssertFalse(report.isPartial)
        let high = CodexRadarSelection(model: "gpt-6.1-sol", effort: "high")
        XCTAssertEqual(try XCTUnwrap(report.summaries[high]?.score), 97.90210570679321, accuracy: 0.000000000001)
        XCTAssertEqual(try XCTUnwrap(report.modelIQ.comparisons[high.key]?.latest?.score), 97.90210570679321, accuracy: 0.000000000001)
    }

    func testServiceKeepsLastGoodScoresDuring428AndRecoversOnTheNextRefresh() async throws {
        let bindingData = try fixtureData("bench-binding-150")
        let session = makeSession()
        defer { session.invalidateAndCancel(); CurrentRadarURLProtocol.respond = nil }
        CurrentRadarURLProtocol.respond = try selectedSummaryResponse(bindingData: bindingData)
        let service = CodexRadarService(session: session)
        let high = CodexRadarSelection(model: "gpt-6.1-sol", effort: "high")
        await service.refresh()
        let original = try XCTUnwrap(service.intelligence)
        let fetchedAt = try XCTUnwrap(service.lastFetchAt)
        XCTAssertEqual(original.summaries.count, 34)

        CurrentRadarURLProtocol.respond = { request in
            request.url?.path == "/data/radar-bench-binding.json" ? (200, bindingData) : (428, Data())
        }
        await service.refresh()

        XCTAssertTrue(service.lastError?.contains("428") == true)
        XCTAssertEqual(service.lastFetchAt, fetchedAt)
        XCTAssertEqual(service.intelligence?.summaries.count, 34)
        XCTAssertEqual(try XCTUnwrap(service.intelligence?.summaries[high]?.score), 97.90210570679321, accuracy: 0.000000000001)
        XCTAssertFalse(service.isRefreshing)

        CurrentRadarURLProtocol.respond = try selectedSummaryResponse(bindingData: bindingData, score: 100.125)
        await service.refresh()

        XCTAssertNil(service.lastError)
        XCTAssertFalse(service.intelligence?.isPartial ?? true)
        XCTAssertEqual(service.intelligence?.summaries.count, 34)
        XCTAssertEqual(service.intelligence?.summaries[high]?.score, 100.125)
        XCTAssertFalse(service.isRefreshing)
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

    private func selectedSummaryResponse(bindingData: Data, score: Double? = nil) throws -> (URLRequest) throws -> (Int, Data) {
        let captured = try fixtureObject("bench-summary-150")
        return { request in
            guard let url = request.url else { return (400, Data()) }
            if url.path == "/data/radar-bench-binding.json" { return (200, bindingData) }
            guard url.path == "/api/radar-bench-score",
                  let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  query.first(where: { $0.name == "view" })?.value == "summary",
                  let model = query.first(where: { $0.name == "model" })?.value,
                  let effort = query.first(where: { $0.name == "effort" })?.value else {
                return (503, Data())
            }
            let isSelected = query.contains { $0.name == "selection" && $0.value == "user-selected-v1" }
                || request.value(forHTTPHeaderField: "X-Radar-Bench-Selection") == "user-selected-v1"
            guard isSelected || (model == "gpt-6.1-sol" && effort == "low") else { return (428, Data()) }
            var payload = captured
            payload["model"] = model
            payload["effort"] = effort
            if let score { payload["score"] = score }
            if var history = payload["history"] as? [String: Any] {
                history["model"] = model
                history["effort"] = effort
                payload["history"] = history
            }
            return (200, try JSONSerialization.data(withJSONObject: payload))
        }
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
