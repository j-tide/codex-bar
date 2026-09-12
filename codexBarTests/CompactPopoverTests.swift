import AppKit
import SwiftUI
import XCTest
@testable import codexAppBar

@MainActor
final class CompactPopoverTests: XCTestCase {
    func testTaskMetadataUsesHookCompatibleHash() {
        XCTAssertEqual(CodexTaskMetadata.taskKey(for: "abc"),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testTitleIndexUsesLatestRenameAndToleratesPartialWrites() {
        let data = Data("""
        {"id":"thread-a","thread_name":"Original prompt"}
        {"id":"thread-b","thread_name":"Another task"}
        {"id":"thread-a","thread_name":"Renamed task","extra":"ignored"}
        {"id":"incomplete"
        """.utf8)
        let key = CodexTaskMetadata.taskKey(for: "thread-a")
        let metadata = CodexTaskMetadata.fromIndex(data, matching: [key])
        XCTAssertEqual(metadata.count, 1)
        XCTAssertEqual(metadata[key]?.title, "Renamed task")
        XCTAssertEqual(metadata[key]?.threadID, "thread-a")
    }

    func testTaskNavigationAcceptsOnlyThreadIdentifiers() {
        let id = "01a08ede-2d87-7303-85f7-a4fe79e5d964"
        XCTAssertEqual(CodexApplicationActivator.taskURL(for: id)?.absoluteString, "codex://threads/\(id)")
        XCTAssertNil(CodexApplicationActivator.taskURL(for: nil))
        XCTAssertNil(CodexApplicationActivator.taskURL(for: "../settings?run=anything"))
    }

    func testMenuBarShowsAllThreeCountsAndExpandsForMultipleDigits() {
        let now = Date()
        func snapshot(running: Int) -> TaskCenterSnapshot {
            var records = (0..<running).map { index in
                TaskActivityRecord(taskKey: "run-\(index)", eventKey: "event-\(index)", state: .running,
                    phase: .processing, projectName: "test", updatedAt: now, source: "UserPromptSubmit")
            }
            for state in [TaskActivityState.needsAttention, .ready] {
                records.append(TaskActivityRecord(taskKey: state.rawValue, eventKey: state.rawValue,
                    state: state, phase: .waitingInput, projectName: "test", updatedAt: now, source: "Stop"))
            }
            return TaskCenterSnapshot(records: records, now: now)
        }
        let small = snapshot(running: 3)
        let large = snapshot(running: 123)
        XCTAssertGreaterThan(StatusTaskCountsView.width(for: large), StatusTaskCountsView.width(for: small))
        let view = StatusTaskCountsView(frame: .zero)
        view.configure(snapshot: large, available: true)
        let strings = view.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertEqual(strings.filter { $0 == "1" }.count, 2)
        XCTAssertTrue(strings.contains("123"))
        view.frame = NSRect(x: 0, y: 0, width: StatusTaskCountsView.width(for: large), height: 24)
        view.layoutSubtreeIfNeeded()
        for label in view.subviews.compactMap({ $0 as? NSTextField }) {
            XCTAssertGreaterThanOrEqual(label.frame.width, label.fittingSize.width, "Count must include native text insets")
            XCTAssertGreaterThanOrEqual(label.frame.height, label.fittingSize.height)
            XCTAssertLessThanOrEqual(label.frame.maxX, view.bounds.maxX)
        }
        view.configure(snapshot: .empty, available: false)
        XCTAssertEqual(view.subviews.compactMap { ($0 as? NSTextField)?.stringValue }.filter { $0 == "0" }.count, 3)
    }

    func testMenuBarAttentionAppearsOnlyWhenNeededAndReclaimsWidth() {
        let now = Date()
        let record = TaskActivityRecord(taskKey: "attention", eventKey: "attention", state: .needsAttention,
            phase: .waitingInput, projectName: "test", updatedAt: now, source: "test")
        let attention = TaskCenterSnapshot(records: [record], now: now)
        let view = StatusTaskCountsView(frame: NSRect(x: 0, y: 0, width: 150, height: 24))
        for (snapshot, visibleCount) in [(TaskCenterSnapshot.empty, 0), (attention, 1), (.empty, 0)] {
            view.configure(snapshot: snapshot, available: true)
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.subviews.compactMap { $0 as? NSTextField }.filter { !$0.isHidden }.count, visibleCount)
        }
        XCTAssertLessThan(StatusTaskCountsView.width(for: .empty), StatusTaskCountsView.width(for: attention))
    }

    func testMenuBarHidesEveryZeroStateIncludingDividerAcrossTransitions() {
        let now = Date()
        let states: [TaskActivityState] = [.needsAttention, .running, .ready]
        let view = StatusTaskCountsView(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        // Reuse the same view: disappearing groups must clear old frames/drawing.
        for mask in [7, 6, 4, 2, 1, 0, 3, 5, 0] {
            let records = states.enumerated().compactMap { index, state -> TaskActivityRecord? in
                guard mask & (1 << index) != 0 else { return nil }
                return TaskActivityRecord(taskKey: state.rawValue, eventKey: state.rawValue,
                    state: state, phase: .processing, projectName: "test", updatedAt: now, source: "Stop")
            }
            let snapshot = TaskCenterSnapshot(records: records, now: now)
            view.configure(snapshot: snapshot, available: true)
            view.layoutSubtreeIfNeeded()
            let labels = view.subviews.compactMap { $0 as? NSTextField }
            XCTAssertEqual(labels.filter { !$0.isHidden }.count, records.count)
            for label in labels where label.isHidden { XCTAssertEqual(label.frame, .zero) }
            let divider = view.layer?.sublayers?.first { $0.frame.width == 0.5 }
            XCTAssertEqual(divider?.isHidden, mask == 0)
            XCTAssertEqual(StatusTaskCountsView.width(for: snapshot) == 0, mask == 0)
        }
    }

    func testMenuBarSpinnerUsesCompositorWithoutMovingCounts() async throws {
        let now = Date()
        let record = TaskActivityRecord(taskKey: "run", eventKey: "run", state: .running,
            phase: .processing, projectName: "test", updatedAt: now, source: "UserPromptSubmit")
        let snapshot = TaskCenterSnapshot(records: [record], now: now)
        let size = NSSize(width: StatusTaskCountsView.width(for: snapshot), height: 24)
        let view = StatusTaskCountsView(frame: NSRect(origin: .zero, size: size))
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: 0), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderBack(nil)
        defer { view.configure(snapshot: .empty, available: true); window.orderOut(nil) }
        view.configure(snapshot: snapshot, available: true)
        view.layoutSubtreeIfNeeded()
        let frames = view.subviews.map(\.frame)
        let host = try XCTUnwrap(view.layer?.sublayers?.first(where: { $0.name == "status-ring-host" }))
        let rotating = try XCTUnwrap(host.sublayers?.first(where: { $0.name == "status-ring-rotation" }))
        let animation = try XCTUnwrap(rotating.animation(forKey: "codexbar.status-ring.rotation") as? CABasicAnimation)
        XCTAssertEqual(animation.keyPath, "transform.rotation.z")
        XCTAssertEqual(animation.duration, 1.4)
        XCTAssertEqual(animation.repeatCount, .infinity)
        try await Task.sleep(for: .milliseconds(100))
        let before = try XCTUnwrap(rotating.presentation()?.value(forKeyPath: "transform.rotation.z") as? Double)
        // Presentation values are synchronized to the client at run-loop commits.
        try await Task.sleep(for: .milliseconds(200))
        let after = try XCTUnwrap(rotating.presentation()?.value(forKeyPath: "transform.rotation.z") as? Double)
        XCTAssertNotEqual(before, after, "The compositor animation advances without changing layout")
        view.configure(snapshot: snapshot, available: true)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(frames, view.subviews.map(\.frame))
        XCTAssertEqual(rotating.bounds, CGRect(x: 0, y: 0, width: 11, height: 11))
        XCTAssertEqual(rotating.position, CGPoint(x: 5.5, y: 5.5))
        view.configure(snapshot: .empty, available: true)
        XCTAssertNil(rotating.animation(forKey: "codexbar.status-ring.rotation"))

    }

    func testUnreadCompletionsPersistAndNewTurnsBecomeUnread() throws {
        let suite = "codexbar.unread-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        func record(_ event: String, state: TaskActivityState = .ready, source: String = "Stop") -> TaskActivityRecord {
            TaskActivityRecord(taskKey: "task", eventKey: event, state: state, phase: .waitingInput,
                               projectName: "codexbar", updatedAt: Date(), source: source)
        }
        let readState = TaskReadState(defaults: defaults)
        XCTAssertTrue(readState.visibleRecords(from: [record("old")]).isEmpty, "Clear already-seen backlog once")
        XCTAssertEqual(readState.visibleRecords(from: [record("new")]).count, 1)
        XCTAssertTrue(readState.visibleRecords(from: [record("new")], knownTaskKeys: []).isEmpty,
                      "Unresolved hook completions must not create phantom unread tasks")
        XCTAssertEqual(readState.visibleRecords(from: [record("new")], knownTaskKeys: ["task"]).count, 1,
                       "A delayed metadata lookup must not mark a real completion as read")
        readState.markRead(record("new"))
        XCTAssertTrue(readState.visibleRecords(from: [record("new")]).isEmpty)
        _ = readState.visibleRecords(from: [])
        let restored = TaskReadState(defaults: defaults)
        XCTAssertTrue(restored.visibleRecords(from: [record("new")]).isEmpty, "Read state survives restart and partial loads")
        XCTAssertEqual(restored.visibleRecords(from: [record("next")]).count, 1)
        XCTAssertEqual(restored.visibleRecords(from: [record("run", state: .running, source: "UserPromptSubmit")]).count, 1)
        for source in ["SessionStart", "Interrupt", "SessionEnd"] {
            XCTAssertTrue(restored.visibleRecords(from: [record("other", source: source)]).isEmpty)
        }
    }

    func testOpeningMetricsAndHeatmapAnimateToStableContent() async throws {
        let content = VStack {
            AnimatedMetric(value: 117).font(.system(size: 28))
            ContributionHeatmap(daily: [:], weeks: 8)
        }
        .padding(20).frame(width: 250, height: 180)
        .background(Color.white).foregroundStyle(.black)
        .environment(\.popupLiveUpdates, true)
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: 0, width: 250, height: 180),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        func capture(_ name: String) throws -> Data {
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: "/tmp/codexbar-motion-\(name).png"))
            return data
        }
        let first = try capture("start")
        try await Task.sleep(for: .milliseconds(1200))
        let final = try capture("end")
        XCTAssertNotEqual(first, final, "Opening must produce visible numeric and cell motion")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(final, try capture("settled"), "Entrance must settle instead of running forever")
    }

    func testManyAccountsKeepPopoverHeightBounded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date()
        let sessions = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        for index in 0..<6 {
            let key = CodexTaskMetadata.taskKey(for: "preview-\(index)")
            let record = TaskActivityRecord(taskKey: key, eventKey: "preview-\(index)",
                state: index == 0 ? .needsAttention : index < 4 ? .running : .ready,
                phase: index == 0 ? .waitingInput : index == 2 ? .compacting : .processing,
                projectName: ["codexbar", "codexbar", "llmops", "fund-pulse", "codexbar", "llmops"][index],
                updatedAt: date.addingTimeInterval(-Double(index)), source: index == 0 ? "Stop" : "UserPromptSubmit")
            try JSONEncoder().encode(record).write(to: sessions.appendingPathComponent(key + ".json"))
        }
        let tasks = TaskCenterService(repository: TaskActivityRepository(sessionsURL: sessions,
            legacyStatusURL: root.appendingPathComponent("legacy.json")), notificationService: TaskNotificationService(), now: Date.init)
        tasks.refresh()
        defer { tasks.stop() }
        XCTAssertEqual(tasks.snapshot.records.count, 6)
        var heights: [CGFloat] = []
        for count in [1, 2, 12, 100] {
            var accounts: [TokenAccount] = []
            for index in 0..<count {
                var account = TokenAccount(email: "person\(index)@example.com", accountId: "user-\(index)",
                    chatgptAccountId: "workspace-\(index)", planType: index == 0 ? "pro" : "plus")
                account.isActive = index == 0
                account.weeklyUsedPercent = Double(index == 0 ? 3 : (index * 7) % 100)
                account.weeklyResetAt = date.addingTimeInterval(6 * 86400)
                account.lastChecked = date
                account.rateLimitResetCreditsAvailableCount = index % 3
                if index > 0 { account.fiveHourUsedPercent = Double(index); account.fiveHourResetAt = date.addingTimeInterval(18000) }
                accounts.append(account)
            }
            let poolURL = root.appendingPathComponent("pool-\(count).json")
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(TokenPool(accounts: accounts)).write(to: poolURL)
            let store = TokenStore(poolURL: poolURL, authURL: root.appendingPathComponent("auth.json"))
            XCTAssertEqual(store.accounts.count, count)
            let content = MenuBarView(liveUpdates: false)
                .environmentObject(store).environmentObject(OAuthManager.shared)
                .environmentObject(LanguageSettings.shared).environmentObject(RefreshFrequencySettings.shared)
                .environmentObject(QuotaDisplaySettings.shared).environmentObject(tasks)
                .environmentObject(CodexHookInstallerService.shared).environmentObject(AppUpdateService.shared)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage)
            heights.append(image.size.height)
            XCTAssertEqual(image.size.width, PopupLayout.width, accuracy: 0.5)
            XCTAssertLessThan(image.size.height, 710)
            if count == 2 || count == 12 {
                // ImageRenderer omits AppKit-backed controls and scroll views; capture the native host.
                let host = NSHostingView(rootView: content)
                let window = NSWindow(contentRect: NSRect(x: -10000, y: 0, width: image.size.width, height: image.size.height),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: .darkAqua)
                window.contentView = host
                window.orderBack(nil)
                host.setFrameSize(image.size)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                host.displayIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: "/tmp/codexbar-compact-popover-\(count).png"))
                window.orderOut(nil)
            }
        }
        XCTAssertEqual(heights.min(), heights.max(), "Account count must not enlarge the popover")
    }
}
