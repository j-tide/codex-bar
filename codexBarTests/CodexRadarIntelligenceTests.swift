import AppKit
import SwiftUI
import XCTest
@testable import codexAppBar

@MainActor
final class CodexRadarIntelligenceTests: XCTestCase {
    func testLiveSchemaFixtureMatchesWeightedWebsiteScoreAndRanking() throws {
        let report = try fixtureReport()
        let matrix = CodexRadarPresentation.matrix(from: report.modelIQ(for: .comprehensive))
        let names = matrix.rankedCellIDs.prefix(6).compactMap { matrix.cell(id: $0)?.displayName }
        XCTAssertEqual(names, ["Astra max", "Astra high", "Astra ultra", "Astra medium", "Astra low", "Sol max"])
        let first = try XCTUnwrap(matrix.cell(id: matrix.bestCellID))
        XCTAssertEqual(first.score, (112.09 * 91 + 140.22102 * 5) / 96, accuracy: 0.00001)
        XCTAssertEqual(report.updatedAt(for: .comprehensive), report.updatedAt(for: .software))
        XCTAssertFalse(matrix.cells.contains { $0.entry.model?.hasPrefix("deepseek") == true })
    }

    func testCompositeExcludesMissingDimensionAndZeroSamples() throws {
        let software = Data(#"{"schema":3,"mode":"equal_latest_3","points":[{"model":"gpt-6-astra","effort":"max","iq":100,"total":90},{"model":"gpt-6-astra","effort":"ultra","iq":150,"total":5},{"model":"gpt-5.6-sol","effort":"max","iq":110,"total":0}]}"#.utf8)
        let visual = Data(#"{"schema":1,"mode":"latest_valid_per_task","type":"visual_spatial_reasoning_summary","points":[{"model":"gpt-6-astra","effort":"max","iq":140,"valid_tasks":10},{"model":"gpt-5.6-sol","effort":"max","iq":140,"valid_tasks":10}]}"#.utf8)
        let report = try CodexRadarIntelligenceReport.decode(software: software, visual: visual)
        let overall = report.modelIQ(for: .comprehensive)
        XCTAssertEqual(overall.comparisons.count, 1)
        XCTAssertEqual(overall.comparisons["gpt-6-astra|max"]?.latest?.score, 104)
        XCTAssertEqual(report.modelIQ(for: .software).comparisons.count, 2)
        XCTAssertEqual(report.modelIQ(for: .visual).comparisons.count, 2)
        XCTAssertNil(report.updatedAt(for: .comprehensive))
    }

    func testWeightedSchemaAcceptsFractionalSampleCounts() throws {
        let software = Data(#"{"schema":2,"mode":"weighted_latest_3","points":[{"model":"gpt-6-astra","effort":"max","iq":100,"weighted_total":2.5}]}"#.utf8)
        let visual = Data(#"{"schema":1,"mode":"latest_valid_per_task","type":"visual_spatial_reasoning_summary","points":[{"model":"gpt-6-astra","effort":"max","iq":140,"valid_tasks":1}]}"#.utf8)
        let report = try CodexRadarIntelligenceReport.decode(software: software, visual: visual)
        let score = try XCTUnwrap(report.modelIQ(for: .comprehensive).comparisons.values.first?.latest?.score)
        XCTAssertEqual(score, 390 / 3.5, accuracy: 0.00001)
    }

    func testUnsupportedSchemaAndEmptyResponsesFailInsteadOfShowingZero() throws {
        let visual = try fixtureData("visual")
        XCTAssertThrowsError(try CodexRadarIntelligenceReport.decode(
            software: Data(#"{"schema":4,"mode":"unknown","points":[]}"#.utf8), visual: visual
        ))
        XCTAssertThrowsError(try CodexRadarIntelligenceReport.decode(
            software: Data(#"{"schema":3,"mode":"equal_latest_3","points":[]}"#.utf8), visual: visual
        ))
    }

    func testServiceLoadsQualityWhenResetEndpointFailsAndRetainsItOnStaleResponse() async throws {
        let software = try fixtureData("software")
        let visual = try fixtureData("visual")
        RadarURLProtocol.respond = { request in
            let path = request.url!.path
            return (path == "/current.json" ? 503 : 200, "HIT", path.contains("visual") ? visual : software)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RadarURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); RadarURLProtocol.respond = nil }
        let service = CodexRadarService(session: session)
        await service.refresh()
        XCTAssertNotNil(service.intelligence)
        XCTAssertNil(service.snapshot)
        XCTAssertNil(service.lastError)
        let successfulFetch = service.lastFetchAt
        let originalScore = service.intelligence?.modelIQ(for: .comprehensive).comparisons["gpt-6-astra|max"]?.latest?.score

        RadarURLProtocol.respond = { request in
            (200, "STALE", request.url!.path.contains("visual") ? visual : software)
        }
        await service.refresh()
        XCTAssertNotNil(service.lastError)
        XCTAssertFalse(service.isRefreshing)
        XCTAssertEqual(service.lastFetchAt, successfulFetch)
        XCTAssertEqual(service.intelligence?.modelIQ(for: .comprehensive).comparisons["gpt-6-astra|max"]?.latest?.score, originalScore)
    }

    func testQualityPanelRendersLightDarkAndUnavailableStatesAtMenuWidth() throws {
        let report = try fixtureReport()
        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .light ? "light" : "dark"
            let content = CodexRadarQualityContent(report: report, isRefreshing: false, error: nil)
                .background(scheme == .light ? Color.white : Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, scheme)
            let size = try render(content, name: name)
            XCTAssertEqual(size.width, 300, accuracy: 0.5)
            XCTAssertLessThan(size.height, 300)
        }
        _ = try render(CodexRadarQualityContent(report: nil, isRefreshing: true, error: nil), name: "loading")
        _ = try render(CodexRadarQualityContent(report: nil, isRefreshing: false, error: "Network unavailable"), name: "error")
        _ = try render(CodexRadarQualityContent(report: report, isRefreshing: false, error: "Network unavailable"), name: "cached")

    }

    private func fixtureData(_ name: String) throws -> Data {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return try Data(contentsOf: directory.appendingPathComponent("Fixtures/Radar/\(name).json"))
    }

    private func fixtureReport() throws -> CodexRadarIntelligenceReport {
        try CodexRadarIntelligenceReport.decode(software: fixtureData("software"), visual: fixtureData("visual"))
    }

    private func render<V: View>(_ content: V, name: String) throws -> CGSize {
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        window.displayIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/codexbar-radar-\(name).png"))
        return size
    }
}

private final class RadarURLProtocol: URLProtocol {
    nonisolated(unsafe) static var respond: ((URLRequest) -> (Int, String, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let respond = Self.respond, let url = request.url else { return }
        let (status, cache, data) = respond(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["X-Codex-Cache": cache])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
