import AppKit
import SwiftUI
import XCTest
@testable import codexAppBar

@MainActor
final class CodexRadarIntelligenceTests: XCTestCase {
    func testServiceDiscoversModelsAndEffortsFromChangingCatalogWithoutAppUpdate() async throws {
        let firstBinding = try benchBindingData(selections: [
            ("gpt-6.1-sol", "high"), ("gpt-7-nova", "adaptive")
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RadarURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); RadarURLProtocol.respond = nil }
        let service = CodexRadarService(session: session)
        RadarURLProtocol.respond = { request in
            if request.url!.path == "/data/radar-bench-binding.json" { return (200, "", firstBinding) }
            guard request.url!.path == "/api/radar-bench-score" else { return (503, "", Data()) }
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let model = query.first { $0.name == "model" }!.value!
            let effort = query.first { $0.name == "effort" }!.value!
            return (200, "", try self.benchSummaryData(binding: firstBinding, model: model, effort: effort, score: 73.5))
        }

        await service.refresh()

        let firstMatrix = CodexRadarPresentation.matrix(from: service.intelligence?.modelIQ)
        XCTAssertNil(service.lastError)
        XCTAssertEqual(firstMatrix.rows.map(\.displayName), ["GPT-7-nova", "GPT-6.1 Sol"])
        XCTAssertEqual(firstMatrix.rows.first?.cell(for: "adaptive")?.score, 73.5)
        XCTAssertTrue(firstMatrix.columns.contains { $0.id == "adaptive" })

        let secondBinding = try benchBindingData(selections: [("gpt-6.1-sol", "high"), ("gpt-7.1-orion", "deep")], catalogVersion: "next-catalog")
        RadarURLProtocol.respond = { request in
            if request.url!.path == "/data/radar-bench-binding.json" { return (200, "", secondBinding) }
            guard request.url!.path == "/api/radar-bench-score" else { return (503, "", Data()) }
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let model = query.first { $0.name == "model" }!.value!
            let effort = query.first { $0.name == "effort" }!.value!
            return (200, "", try self.benchSummaryData(binding: secondBinding, model: model, effort: effort, score: 81.25))
        }

        await service.refresh()

        let secondMatrix = CodexRadarPresentation.matrix(from: service.intelligence?.modelIQ)
        XCTAssertEqual(secondMatrix.rows.map(\.displayName), ["GPT-7.1-orion", "GPT-6.1 Sol"])
        XCTAssertEqual(secondMatrix.rows.first?.cell(for: "deep")?.score, 81.25)
        XCTAssertFalse(secondMatrix.columns.contains { $0.id == "adaptive" })
    }

    func testPublicSummariesPreserveMissingScoresRealZeroAndCoverage() throws {
        let data = try benchBindingData(selections: [("gpt-6.1-sol", "low"), ("gpt-6.1-sol", "xhigh"), ("gpt-6.1-sol", "high")])
        let binding = try CodexRadarBenchBinding.decode(data)
        var summaries: [CodexRadarSelection: CodexRadarBenchSummary] = [:]
        for selection in binding.selections {
            let score: Double? = selection.effort == "low" ? 75 : selection.effort == "xhigh" ? 0 : nil
            let coverage = selection.effort == "low" ? 12 : selection.effort == "xhigh" ? 1 : 0
            summaries[selection] = try CodexRadarBenchSummary.decode(
                benchSummaryData(binding: data, model: selection.model, effort: selection.effort, score: score, coverage: coverage),
                binding: binding, selection: selection
            )
        }
        let report = CodexRadarIntelligenceReport(binding: binding, summaries: summaries)
        let matrix = CodexRadarPresentation.matrix(from: report.modelIQ)
        let row = try XCTUnwrap(matrix.rows.first)
        XCTAssertEqual(row.displayName, "GPT-6.1 Sol")
        XCTAssertEqual(row.cell(for: "low")?.score, 75)
        XCTAssertEqual(row.cell(for: "low")?.coverageText, "12/64")
        XCTAssertEqual(row.cell(for: "xhigh")?.score, 0)
        XCTAssertEqual(row.cell(for: "xhigh")?.coverageText, "1/64")
        XCTAssertNil(row.cell(for: "high"))
        XCTAssertEqual(matrix.rankedCellIDs.count, 2)
        XCTAssertFalse(report.isPartial)
    }

    func testSummaryRejectsMismatchedIdentityCatalogPolicyAndInvalidScores() throws {
        let data = try benchBindingData(selections: [("gpt-6.1-sol", "high")])
        let binding = try CodexRadarBenchBinding.decode(data)
        let selection = try XCTUnwrap(binding.selections.first)
        let valid = try XCTUnwrap(JSONSerialization.jsonObject(with: benchSummaryData(
            binding: data, model: selection.model, effort: selection.effort, score: 73.5
        )) as? [String: Any])
        let mismatches: [(String, Any)] = [
            ("schema", "legacy"), ("score_version", "legacy-iq"),
            ("benchmark", "other-benchmark"), ("catalog_version", "old-catalog"),
            ("task_set_sha256", String(repeating: "0", count: 64)),
            ("model", "gpt-6-sol"), ("effort", "low"), ("required_tasks", 63),
            ("coverage", -1), ("coverage", 65), ("source_counts", [:]),
            ("score_status", "missing_current_result"), ("score", -1), ("score", 101),
            ("score", NSNull()), ("scoring_policy_version", "unknown-policy")
        ]
        for (key, value) in mismatches {
            var invalid = valid
            invalid[key] = value
            XCTAssertThrowsError(try CodexRadarBenchSummary.decode(
                JSONSerialization.data(withJSONObject: invalid), binding: binding, selection: selection
            ), key)
        }
        XCTAssertThrowsError(try CodexRadarBenchSummary.decode(
            benchSummaryData(binding: data, model: selection.model, effort: selection.effort, score: 0, coverage: 0),
            binding: binding, selection: selection
        ))
    }

    func testBindingRejectsDisabledUnverifiedEmptyAndDuplicateCatalogs() throws {
        let valid = try XCTUnwrap(JSONSerialization.jsonObject(with: benchBindingData(
            selections: [("gpt-6.1-sol", "high")]
        )) as? [String: Any])
        let invalidValues: [(String, Any)] = [
            ("enabled", false), ("interface_confirmed", false), ("production_read_verified", false),
            ("catalog_version", ""), ("task_set_sha256", "bad-digest"), ("source_counts", ["deepswe": 1]),
            ("model_efforts", []),
            ("model_efforts", [["model": "gpt-6.1-sol", "effort": "high"], ["model": "gpt-6.1-sol", "effort": "high"]]),
            ("model_efforts", [["model": " ", "effort": "high"]]),
            ("model_efforts", [["model": "gpt-6.1-sol", "effort": " "]])
        ]
        for (key, value) in invalidValues {
            var invalid = valid
            invalid[key] = value
            XCTAssertThrowsError(try CodexRadarBenchBinding.decode(JSONSerialization.data(withJSONObject: invalid)), key)
        }
    }

    func testServiceKeepsCatalogRowsDuringPartialOutageAndCachedScoresOnTotalFailure() async throws {
        let binding = try benchBindingData(selections: [("gpt-6.1-sol", "low"), ("gpt-7-nova", "adaptive")])
        let valid = try benchSummaryData(binding: binding, model: "gpt-6.1-sol", effort: "low", score: 75, coverage: 12)
        RadarURLProtocol.respond = { request in
            switch request.url!.path {
            case "/data/radar-bench-binding.json": return (200, "", binding)
            case "/api/radar-bench-score":
                return request.url!.query!.contains("gpt-6.1-sol") ? (200, "HIT", valid) : (503, "", Data())
            default: return (503, "", Data())
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RadarURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); RadarURLProtocol.respond = nil }
        let service = CodexRadarService(session: session)
        await service.refresh()
        let partial = try XCTUnwrap(service.intelligence)
        XCTAssertTrue(partial.isPartial)
        XCTAssertNil(service.lastError)
        XCTAssertNil(service.snapshot)
        let matrix = CodexRadarPresentation.matrix(from: partial.modelIQ)
        XCTAssertEqual(matrix.rows.map(\.displayName), ["GPT-7-nova", "GPT-6.1 Sol"])
        XCTAssertTrue(matrix.rows[0].cellsByEffort.isEmpty)
        XCTAssertEqual(matrix.rows[1].cell(for: "low")?.score, 75)
        let fetchedAt = service.lastFetchAt
        let size = try render(CodexRadarQualityContent(report: partial, isRefreshing: false, error: nil), name: "bench-partial")
        XCTAssertLessThanOrEqual(size.height, CodexRadarQualityContent.panelHeight(rowCount: matrix.rows.count, isPartial: true))

        RadarURLProtocol.respond = { request in
            (request.url!.path == "/data/radar-bench-binding.json" ? 200 : 503, "", binding)
        }
        await service.refresh()
        XCTAssertNotNil(service.lastError)
        XCTAssertEqual(service.lastFetchAt, fetchedAt)
        XCTAssertEqual(service.intelligence?.modelIQ.comparisons[CodexRadarSelection(model: "gpt-6.1-sol", effort: "low").key]?.latest?.score, 75)
        XCTAssertFalse(service.isRefreshing)

        RadarURLProtocol.respond = { request in
            if request.url!.path == "/data/radar-bench-binding.json" { return (200, "", binding) }
            if request.url!.path != "/api/radar-bench-score" { return (503, "", Data()) }
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let model = query.first { $0.name == "model" }!.value!
            let effort = query.first { $0.name == "effort" }!.value!
            return (200, "HIT", try self.benchSummaryData(binding: binding, model: model, effort: effort, score: 80))
        }
        await service.refresh()
        XCTAssertNil(service.lastError)
        XCTAssertFalse(service.intelligence?.isPartial ?? true)
        XCTAssertEqual(service.intelligence?.modelIQ.comparisons[CodexRadarSelection(model: "gpt-7-nova", effort: "adaptive").key]?.latest?.score, 80)
    }

    func testServiceShowsCatalogEvenBeforeAnyModelHasGrades() async throws {
        let binding = try benchBindingData(selections: [("gpt-6.1-sol", "high"), ("gpt-7-nova", "adaptive")])
        RadarURLProtocol.respond = { request in
            if request.url!.path == "/data/radar-bench-binding.json" { return (200, "", binding) }
            if request.url!.path != "/api/radar-bench-score" { return (503, "", Data()) }
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            return (200, "HIT", try self.benchSummaryData(
                binding: binding, model: query.first { $0.name == "model" }!.value!,
                effort: query.first { $0.name == "effort" }!.value!, score: nil, coverage: 0
            ))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RadarURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); RadarURLProtocol.respond = nil }
        let service = CodexRadarService(session: session)
        await service.refresh()
        XCTAssertNil(service.lastError)
        let report = try XCTUnwrap(service.intelligence)
        let matrix = CodexRadarPresentation.matrix(from: report.modelIQ)
        XCTAssertEqual(matrix.rows.count, 2)
        XCTAssertTrue(matrix.cells.isEmpty)
        XCTAssertNil(matrix.bestCellID)
        XCTAssertFalse(report.isPartial)
    }

    func testCapturedPublicCatalogShowsGPT61AndRendersAtMenuWidth() throws {
        let report = try fixtureReport()
        let matrix = CodexRadarPresentation.matrix(from: report.modelIQ)
        XCTAssertEqual(matrix.rows.count, 6)
        let row = try XCTUnwrap(matrix.rows.first { $0.displayName == "GPT-6.1 Sol" })
        XCTAssertEqual(row.cell(for: "low")?.score, 75)
        XCTAssertEqual(row.cell(for: "xhigh")?.score, 0)
        XCTAssertEqual(matrix.columns.map(\.id), ["low", "medium", "high", "xhigh", "max", "ultra"])
        let size = try render(CodexRadarQualityContent(report: report, isRefreshing: false, error: nil)
            .background(Color.white).environment(\.colorScheme, .light), name: "bench-captured-public")
        XCTAssertEqual(size.width, PopupLayout.columnWidth, accuracy: 0.5)
        XCTAssertLessThanOrEqual(size.height, CodexRadarQualityContent.panelHeight(rowCount: matrix.rows.count, isPartial: report.isPartial))
    }

    func testQualityPanelRendersLightDarkLoadingAndCachedStates() throws {
        let report = try fixtureReport()
        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .light ? "bench-light" : "bench-dark"
            let content = CodexRadarQualityContent(report: report, isRefreshing: false, error: nil)
                .background(scheme == .light ? Color.white : Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, scheme)
            let size = try render(content, name: name)
            XCTAssertEqual(size.width, PopupLayout.columnWidth, accuracy: 0.5)
        }
        _ = try render(CodexRadarQualityContent(report: nil, isRefreshing: true, error: nil), name: "bench-loading")
        _ = try render(CodexRadarQualityContent(report: nil, isRefreshing: false, error: "HTTP 503"), name: "bench-error")
        _ = try render(CodexRadarQualityContent(report: report, isRefreshing: false, error: "HTTP 503"), name: "bench-cached")
    }

    func testMatrixPanelKeepsAllCatalogModelsAndTheThreeScoredSelections() throws {
        let report = try fixtureReport()
        XCTAssertEqual(report.binding.selections.count, 34)
        let matrix = CodexRadarPresentation.matrix(from: report.modelIQ)
        XCTAssertEqual(matrix.rows.count, 6)
        XCTAssertEqual(matrix.columns.map(\.id), ["low", "medium", "high", "xhigh", "max", "ultra"])
        XCTAssertEqual(matrix.cells.count, 3)
        let size = try render(CodexRadarQualityContent(report: report, isRefreshing: false, error: nil)
            .background(Color.white).environment(\.colorScheme, .light), name: "matrix-captured-public")

        XCTAssertGreaterThanOrEqual(size.height, 252, "All six model rows must remain visible in the matrix")
        XCTAssertLessThanOrEqual(size.height, 296)
        XCTAssertEqual(CodexRadarQualityContent.panelHeight(rowCount: 6, isPartial: false), 296)
    }

    func testEntirelyUnscoredCatalogStillShowsTheModelMatrixAndPartialNotice() throws {
        let data = try fixtureData("bench-binding")
        let binding = try CodexRadarBenchBinding.decode(data)
        var summaries: [CodexRadarSelection: CodexRadarBenchSummary] = [:]
        for selection in binding.selections {
            summaries[selection] = try CodexRadarBenchSummary.decode(
                benchSummaryData(binding: data, model: selection.model, effort: selection.effort, score: nil, coverage: 0),
                binding: binding, selection: selection
            )
        }
        let report = CodexRadarIntelligenceReport(binding: binding, summaries: summaries)
        let size = try render(CodexRadarQualityContent(report: report, isRefreshing: false, error: nil)
            .background(Color.white).environment(\.colorScheme, .light), name: "matrix-no-grades")

        XCTAssertGreaterThanOrEqual(size.height, 252, "Unscored models remain visible with unavailable cells")
        XCTAssertLessThanOrEqual(size.height, 296)

        let missing = try XCTUnwrap(binding.selections.first)
        let partial = CodexRadarIntelligenceReport(binding: binding, summaries: summaries.filter { $0.key != missing })
        let partialSize = try render(CodexRadarQualityContent(report: partial, isRefreshing: false, error: nil)
            .background(Color.white).environment(\.colorScheme, .light), name: "matrix-no-grades-partial")
        XCTAssertGreaterThan(partialSize.height, size.height, "The unscored matrix must still include the partial-fetch notice")
    }

    func testLargeCatalogKeepsEveryModelWithinAScrollingPanel() throws {
        let data = try benchBindingData(selections: (0..<40).map { ("gpt-7.\($0)-sol", "high") })
        let binding = try CodexRadarBenchBinding.decode(data)
        var summaries: [CodexRadarSelection: CodexRadarBenchSummary] = [:]
        for selection in binding.selections {
            summaries[selection] = try CodexRadarBenchSummary.decode(
                benchSummaryData(binding: data, model: selection.model, effort: selection.effort, score: 73.5),
                binding: binding, selection: selection
            )
        }
        let report = CodexRadarIntelligenceReport(binding: binding, summaries: summaries)
        XCTAssertEqual(CodexRadarPresentation.matrix(from: report.modelIQ).rows.count, 40)
        XCTAssertLessThanOrEqual(CodexRadarQualityContent.panelHeight(rowCount: 40, isPartial: false), 360)
        let size = try render(CodexRadarQualityContent(report: report, isRefreshing: false, error: nil), name: "bench-large-catalog", checkScrolling: true)
        XCTAssertLessThanOrEqual(size.height, 360)
    }

    func testLargeCatalogKeepsTheFullMenuInsideACompactScreen() async throws {
        let binding = try benchBindingData(selections: (0..<40).map { ("gpt-7.\($0)-sol", "high") })
        RadarURLProtocol.respond = { request in
            if request.url!.path == "/data/radar-bench-binding.json" { return (200, "", binding) }
            if request.url!.path != "/api/radar-bench-score" { return (503, "", Data()) }
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            return (200, "HIT", try self.benchSummaryData(
                binding: binding, model: query.first { $0.name == "model" }!.value!,
                effort: query.first { $0.name == "effort" }!.value!, score: 73.5
            ))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RadarURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); RadarURLProtocol.respond = nil }
        let service = CodexRadarService(session: session)
        await service.refresh()
        XCTAssertEqual(CodexRadarPresentation.matrix(from: service.intelligence?.modelIQ).rows.count, 40)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let poolURL = root.appendingPathComponent("pool.json")
        let accounts = (0..<3).map { TokenAccount(email: "preview\($0)@example.com", accountId: "preview-\($0)", planType: "pro10x") }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(TokenPool(accounts: accounts)).write(to: poolURL)
        let store = TokenStore(poolURL: poolURL, authURL: root.appendingPathComponent("auth.json"))
        let tasks = TaskCenterService(repository: TaskActivityRepository(
            sessionsURL: root.appendingPathComponent("sessions"), legacyStatusURL: root.appendingPathComponent("legacy.json")
        ), notificationService: TaskNotificationService(), now: Date.init)
        defer { tasks.stop() }
        let content = MenuBarView(liveUpdates: false, radar: service)
            .environmentObject(store).environmentObject(OAuthManager.shared)
            .environmentObject(LanguageSettings.shared).environmentObject(RefreshFrequencySettings.shared)
            .environmentObject(QuotaDisplaySettings.shared).environmentObject(tasks)
            .environmentObject(CodexHookInstallerService.shared).environmentObject(AppUpdateService.shared)
        let placement = MenuBarPopoverPlacement()
        placement.availableHeight = 576 // 604-point visible screen, less bottom margin and shadow.
        let size = try render(MenuBarPopoverRoot(placement: placement, content: content),
                              name: "bench-large-compact-menu", width: PopupLayout.width + 48, checkScrolling: true)
        XCTAssertLessThanOrEqual(size.height, 600)
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 604)
        let anchor = NSRect(x: 800, y: 604, width: 30, height: 24)
        let frame = MenuBarPopoverPlacement.frame(size: size, anchor: anchor, screen: screen)
        XCTAssertGreaterThanOrEqual(frame.minY, screen.minY + 4)
        XCTAssertLessThanOrEqual(frame.maxY, anchor.minY)
    }

    func testSelectionIdentityCannotCollideWhenModelOrEffortContainsASeparator() throws {
        let first = CodexRadarSelection(model: "gpt-7|nova", effort: "high")
        let second = CodexRadarSelection(model: "gpt-7", effort: "nova|high")
        XCTAssertNotEqual(first.key, second.key)
        guard first.key != second.key else { return }
        let data = try benchBindingData(selections: [(first.model, first.effort), (second.model, second.effort)])
        let binding = try CodexRadarBenchBinding.decode(data)
        var summaries: [CodexRadarSelection: CodexRadarBenchSummary] = [:]
        for selection in binding.selections {
            summaries[selection] = try CodexRadarBenchSummary.decode(
                benchSummaryData(binding: data, model: selection.model, effort: selection.effort, score: 73.5),
                binding: binding, selection: selection
            )
        }
        let report = CodexRadarIntelligenceReport(binding: binding, summaries: summaries)
        XCTAssertEqual(report.modelIQ.comparisons.count, 2)
        XCTAssertEqual(CodexRadarPresentation.matrix(from: report.modelIQ).cells.count, 2)
    }

    private func fixtureData(_ name: String) throws -> Data {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return try Data(contentsOf: directory.appendingPathComponent("Fixtures/Radar/\(name).json"))
    }

    private func benchBindingData(selections: [(String, String)], catalogVersion: String? = nil) throws -> Data {
        var binding = try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData("bench-binding")) as? [String: Any])
        binding["model_efforts"] = selections.map { ["model": $0.0, "effort": $0.1] }
        if let catalogVersion { binding["catalog_version"] = catalogVersion }
        return try JSONSerialization.data(withJSONObject: binding)
    }

    private func benchSummaryData(binding: Data, model: String, effort: String, score: Double?, coverage: Int = 64) throws -> Data {
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: binding) as? [String: Any])
        var summary = try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData("bench-summary")) as? [String: Any])
        for key in ["benchmark", "catalog_version", "task_set_sha256", "source_counts"] { summary[key] = catalog[key] }
        summary["model"] = model
        summary["effort"] = effort
        summary["score"] = score.map { $0 as Any } ?? NSNull()
        summary["coverage"] = coverage
        summary["score_status"] = coverage == 0 ? "missing_current_result" : coverage == 64 ? "complete" : "provisional"
        return try JSONSerialization.data(withJSONObject: summary)
    }

    private func fixtureReport() throws -> CodexRadarIntelligenceReport {
        let binding = try CodexRadarBenchBinding.decode(fixtureData("bench-binding"))
        let payloads = try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData("bench-public-summaries")) as? [[String: Any]])
        var summaries: [CodexRadarSelection: CodexRadarBenchSummary] = [:]
        for payload in payloads {
            let selection = CodexRadarSelection(model: try XCTUnwrap(payload["model"] as? String), effort: try XCTUnwrap(payload["effort"] as? String))
            summaries[selection] = try CodexRadarBenchSummary.decode(JSONSerialization.data(withJSONObject: payload), binding: binding, selection: selection)
        }
        return CodexRadarIntelligenceReport(binding: binding, summaries: summaries)
    }

    private func render<V: View>(_ content: V, name: String, width: CGFloat? = nil, checkScrolling: Bool = false) throws -> CGSize {
        let hosting = NSHostingView(rootView: content.environment(\.popupLiveUpdates, false).frame(width: width ?? PopupLayout.columnWidth))
        var size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        size = hosting.fittingSize
        window.setContentSize(size)
        hosting.setFrameSize(size)
        hosting.layoutSubtreeIfNeeded()
        if checkScrolling {
            func scrollViews(in view: NSView) -> [NSScrollView] {
                (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
            }
            let scroll = try XCTUnwrap(scrollViews(in: hosting).first { ($0.documentView?.bounds.height ?? 0) >= 1200 })
            let document = try XCTUnwrap(scroll.documentView)
            XCTAssertGreaterThan(document.bounds.height, scroll.contentView.bounds.height)
            document.scrollToVisible(NSRect(x: 0, y: document.bounds.maxY - 1, width: 1, height: 1))
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0, "The final catalog rows must be reachable by scrolling")
        }
        window.displayIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/codexbar-radar-\(name).png"))
        return size
    }
}

private final class RadarURLProtocol: URLProtocol {
    nonisolated(unsafe) static var respond: ((URLRequest) throws -> (Int, String, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let respond = Self.respond, let url = request.url else { return }
        let status: Int
        let cache: String
        let data: Data
        do { (status, cache, data) = try respond(request) }
        catch { client?.urlProtocol(self, didFailWithError: error); return }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["X-Radar-Bench-Cache": cache])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
