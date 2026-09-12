import AppKit
import Combine
import QuartzCore
import OSLog
import UserNotifications
import SwiftUI

@main
struct codexBarApp: App {
    @NSApplicationDelegateAdaptor(CallbackApplicationDelegate.self) private var applicationDelegate
    init() {
        // 单元测试会把测试包注入应用进程；此时禁止启动真实刷新、hooks 和更新任务。
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        TokenStore.shared.startMonitoringActiveAuthFile()
        // App 级后台续期，脱离菜单 View 生命周期（菜单关闭时 View 不存在，其内 Timer 不跑）
        BackgroundRefresher.shared.start(interval: RefreshFrequencySettings.shared.selection.backgroundInterval)
        CodexRadarService.shared.start()
        CodexHookInstallerService.shared.start()
        TaskCenterService.shared.onRequestOpenCodex = {
            CodexApplicationActivator.activate()
        }
        TaskCenterService.shared.start()
        AppUpdateService.shared.startPeriodicChecks()
        AppStatusBarController.shared.start(
            store: TokenStore.shared,
            oauth: OAuthManager.shared,
            language: LanguageSettings.shared,
            refreshFrequency: RefreshFrequencySettings.shared,
            quotaDisplay: QuotaDisplaySettings.shared,
            taskCenter: TaskCenterService.shared,
            codexHookInstaller: CodexHookInstallerService.shared
        )
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class CallbackApplicationDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: OAuthCallbackPage.isReturnURL) else { return }
        AppStatusBarController.shared.openFromCallback()
    }
}

@MainActor
private final class AppStatusBarController: NSObject {
    static let shared = AppStatusBarController()

    private var statusItem: NSStatusItem?
    private var popover: MenuBarGlassPanel?
    private var cancellables: Set<AnyCancellable> = []
    private var capsuleView: StatusBarCapsuleView?
    private var lastStatusItemWidth: CGFloat = 0
    private var isRefreshingFromMenu = false

    private weak var store: TokenStore?
    private weak var oauth: OAuthManager?
    private weak var language: LanguageSettings?
    private weak var refreshFrequency: RefreshFrequencySettings?
    private weak var quotaDisplay: QuotaDisplaySettings?
    private weak var taskCenter: TaskCenterService?
    private weak var codexHookInstaller: CodexHookInstallerService?

    func start(
        store: TokenStore,
        oauth: OAuthManager,
        language: LanguageSettings,
        refreshFrequency: RefreshFrequencySettings,
        quotaDisplay: QuotaDisplaySettings,
        taskCenter: TaskCenterService,
        codexHookInstaller: CodexHookInstallerService
    ) {
        guard statusItem == nil else { return }

        NSApplication.shared.setActivationPolicy(.accessory)

        self.store = store
        self.oauth = oauth
        self.language = language
        self.refreshFrequency = refreshFrequency
        self.quotaDisplay = quotaDisplay
        self.taskCenter = taskCenter
        self.codexHookInstaller = codexHookInstaller

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.image = nil
            button.title = ""
            button.imagePosition = .noImage
            button.wantsLayer = true
            button.layer?.masksToBounds = false
            // Toggle at press time, before AppKit starts tracking the status item
            // and activation/dismissal notifications can change panel visibility.
            button.sendAction(on: [.leftMouseDown, .rightMouseUp])
            installStatusContentView(in: button)
        }

        installObservers()
        updateStatusItem()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--benchmark-popover") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                var samples: [Double] = []
                for _ in 0..<6 {
                    let start = CACurrentMediaTime()
                    self.showMenuPopover()
                    self.popover?.contentView?.layoutSubtreeIfNeeded()
                    self.popover?.contentView?.displayIfNeeded()
                    samples.append((CACurrentMediaTime() - start) * 1_000)
                    try? await Task.sleep(for: .seconds(1))
                    self.popover?.close()
                    try? await Task.sleep(for: .milliseconds(250))
                }
                if let data = try? JSONEncoder().encode(samples) {
                    try? data.write(to: URL(fileURLWithPath: "/tmp/codexbar-popup-benchmark.json"))
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--open-notification-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.openNotificationSettings { success in
                    Logger(subsystem: Bundle.main.bundleIdentifier ?? "codexbar", category: "TaskNotifications")
                        .notice("Settings handoff completed: success=\(success)")
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--notification-status") {
            Task { @MainActor in
                let service = TaskNotificationService.shared
                await service.refreshAuthorizationStatusNow()
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "codexbar", category: "TaskNotifications")
                    .notice("Notification status check: enabled=\(service.isEnabled), status=\(service.authorizationStatus.rawValue)")
                let center = UNUserNotificationCenter.current()
                let settings = await center.notificationSettings()
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "codexbar", category: "TaskNotifications")
                    .notice("Notification presentation: alerts=\(settings.alertSetting.rawValue), style=\(settings.alertStyle.rawValue), sound=\(settings.soundSetting.rawValue)")
                var diagnosticID: String?
                if ProcessInfo.processInfo.arguments.contains("--test-task-notification"), service.isEnabled {
                    let id = SystemTaskNotificationClient.identifierPrefix + "diagnostic-" + UUID().uuidString
                    let content = UNMutableNotificationContent()
                    content.title = L.zh ? "CodexAppBar 通知测试" : "CodexAppBar notification test"
                    content.body = L.zh ? "这是一条测试提醒，用于确认系统通知可以正常接收。" : "This test checks that macOS can receive notifications from CodexAppBar."
                    content.sound = .default
                    do {
                        try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
                        diagnosticID = id
                    } catch {
                        Logger(subsystem: Bundle.main.bundleIdentifier ?? "codexbar", category: "TaskNotifications")
                            .error("Diagnostic notification rejected: \(error.localizedDescription, privacy: .public)")
                    }
                }
                try? await Task.sleep(for: .seconds(3))
                let delivered = await center.deliveredNotifications()
                if let diagnosticID {
                    let received = delivered.contains { $0.request.identifier == diagnosticID }
                    Logger(subsystem: Bundle.main.bundleIdentifier ?? "codexbar", category: "TaskNotifications")
                        .notice("Diagnostic notification delivered: \(received)")
                }
                let completedCount = delivered.filter {
                    $0.request.identifier.hasPrefix(SystemTaskNotificationClient.identifierPrefix)
                        && $0.request.content.title == L.taskCompletedNotificationTitle
                }.count
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "codexbar", category: "TaskNotifications")
                    .notice("Delivered completion notifications: \(completedCount)")
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--request-notification-permission") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                NSApplication.shared.activate(ignoringOtherApps: true)
                Task { @MainActor in
                    let service = TaskNotificationService.shared
                    let enabled = await service.enable()
                    Logger(subsystem: Bundle.main.bundleIdentifier ?? "codexbar", category: "TaskNotifications")
                        .notice("Permission verification completed: enabled=\(enabled), status=\(service.authorizationStatus.rawValue)")
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--show-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showMenuPopover()
                if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--snapshot-popover=") }) {
                    let path = String(argument.dropFirst("--snapshot-popover=".count))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self?.exportDebugSnapshot(to: path)
                    }
                }
            }
        }
        #endif
    }

    #if DEBUG
    /// Capture our own native views without screen-recording access or fixture data.
    private func exportDebugSnapshot(to path: String, retries: Int = 20) {
        if retries > 0, CodexRadarService.shared.isRefreshing || TokenStatsService.shared.loading {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.exportDebugSnapshot(to: path, retries: retries - 1)
            }
            return
        }
        // Data can arrive immediately before capture; let entrance counters settle.
        if retries >= 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.exportDebugSnapshot(to: path, retries: -1)
            }
            return
        }
        func capture(_ view: NSView?, path: String) {
            guard let view else { return }
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
        capture(popover?.contentViewController?.view, path: path)
        capture(capsuleView, path: path + "-menubar.png")
    }
    #endif

    func openFromCallback() {
        if popover?.isVisible == true { popover?.makeKeyAndOrderFront(nil) }
        else { showMenuPopover() }
    }

    @objc private func togglePopover(_ sender: Any?) {
        if PopupModalPresenter.isPresenting {
            NSApp.modalWindow?.makeKeyAndOrderFront(nil)
            return
        }
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
            showContextMenu(event: event)
            return
        }
        if popover?.isShown == true {
            popover?.performClose(nil)
            return
        }
        showMenuPopover()
    }

    private func showContextMenu(event: NSEvent) {
        guard let button = statusItem?.button else { return }
        popover?.close()
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, _ action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            return item
        }
        _ = add(L.zh ? "打开面板" : "Open Panel", #selector(openPanelFromMenu))
        _ = add(L.zh ? "打开 Codex" : "Open Codex", #selector(openCodexFromMenu))
        menu.addItem(.separator())
        let refresh = add(isRefreshingFromMenu ? L.refreshing : L.refreshUsage, #selector(refreshFromMenu))
        refresh.isEnabled = !isRefreshingFromMenu
        let lights = add(L.zh ? "显示任务状态" : "Show Task Status", #selector(toggleStatusFromMenu))
        lights.state = quotaDisplay?.showStatusLights == true ? .on : .off
        menu.addItem(.separator())
        _ = add(L.quit + " CodexAppBar…", #selector(quitFromMenu))
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc private func openPanelFromMenu() { showMenuPopover() }
    @objc private func openCodexFromMenu() { CodexApplicationActivator.activate() }
    @objc private func toggleStatusFromMenu() { quotaDisplay?.toggleStatusLights() }
    @objc private func quitFromMenu() { AppQuitConfirmation.request() }
    @objc private func refreshFromMenu() {
        guard !isRefreshingFromMenu, let store else { return }
        isRefreshingFromMenu = true
        Task { @MainActor [weak self] in
            defer { self?.isRefreshingFromMenu = false }
            async let radarRefresh: Void = CodexRadarService.shared.refresh()
            await RefreshService.shared.refreshExpiring(store: store)
            await WhamService.shared.refreshAll(store: store)
            await radarRefresh
            TokenStatsService.shared.refresh()
            self?.taskCenter?.refresh()
        }
    }

    private func installObservers() {
        guard let store, let language, let quotaDisplay, let taskCenter, let codexHookInstaller else { return }

        store.$accounts
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        language.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        quotaDisplay.$amountMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        quotaDisplay.$showStatusLights
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        taskCenter.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        codexHookInstaller.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
    }

    private func installStatusContentView(in button: NSStatusBarButton) {
        let view = StatusBarCapsuleView()
        view.frame = button.bounds
        view.autoresizingMask = [.width, .height]
        button.addSubview(view)
        capsuleView = view
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button,
              let capsuleView,
              let store,
              let quotaDisplay,
              let taskCenter,
              let codexHookInstaller else { return }
        let quotaState = Self.quotaState(from: store, amountMode: quotaDisplay.amountMode)
        let iconName = Self.iconName(from: store)
        let width = StatusBarCapsuleView.width(
            for: quotaState,
            showStatusLights: quotaDisplay.showStatusLights,
            snapshot: taskCenter.snapshot
        )
        let light: CodexSessionLight = codexHookInstaller.state.needsAction
            ? .offline
            : taskCenter.snapshot.aggregateLight

        if abs(lastStatusItemWidth - width) > 0.5 {
            statusItem?.length = width
            lastStatusItemWidth = width
        }

        capsuleView.frame = button.bounds
        capsuleView.configure(
            iconName: iconName,
            quotaState: quotaState,
            light: light,
            snapshot: taskCenter.snapshot,
            showStatusLights: quotaDisplay.showStatusLights
        )
        button.toolTip = Self.taskStatusToolTip(
            snapshot: taskCenter.snapshot,
            hookState: codexHookInstaller.state
        )
    }

    private func showMenuPopover() {
        guard let button = statusItem?.button,
              let store,
              let oauth,
              let language,
              let refreshFrequency,
              let quotaDisplay,
              let taskCenter,
              let codexHookInstaller else { return }

        self.popover?.close()
        let popover = MenuBarGlassPanel()
        let appearance = UserDefaults.standard.string(forKey: "popupAppearance") ?? "system"
        popover.appearance = appearance == "dark" ? NSAppearance(named: .darkAqua)
            : appearance == "light" ? NSAppearance(named: .aqua) : nil
        popover.contentViewController = FirstMouseHostingController(
            rootView: MenuBarPopoverRoot(placement: popover.placement, content: MenuBarView(onAppearanceChange: { [weak popover] appearance in
                popover?.setAppearance(appearance)
            }, onOpenNotificationSettings: { [weak self] completion in
                self?.openNotificationSettings(completion: completion)
            })
                .environmentObject(store)
                .environmentObject(oauth)
                .environmentObject(language)
                .environmentObject(refreshFrequency)
                .environmentObject(quotaDisplay)
                .environmentObject(taskCenter)
                .environmentObject(codexHookInstaller)
                .environmentObject(AppUpdateService.shared)),
            onSizeChange: { [weak popover] in popover?.resizeToFitContent() }
        )
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func openNotificationSettings(completion: @escaping (Bool) -> Void) {
        popover?.close()
        NotificationSettingsOpener.shared.open { success in
            completion(success)
            if !success {
                NSApplication.shared.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = L.zh ? "无法打开通知设置" : "Could not open Notification Settings"
                alert.informativeText = L.zh ? "请从苹果菜单打开系统设置，在“通知”中找到 CodexAppBar。" : "Open System Settings from the Apple menu, then find CodexAppBar under Notifications."
                PopupModalPresenter.run { alert.runModal() }
            }
        }
    }

    private static func quotaState(from store: TokenStore, amountMode: QuotaAmountMode) -> StatusBarQuotaState {
        guard let active = store.accounts.first(where: { $0.isActive }) else {
            return StatusBarQuotaState.empty
        }
        let weeklyDisplayPercent = amountMode.displayPercent(forUsedPercent: active.weeklyUsedPercent)
        let fiveHourDisplayPercent = active.hasFiveHourQuota
            ? active.fiveHourUsedPercent.map {
                amountMode.displayPercent(forUsedPercent: $0)
            }
            : nil
        let text: String
        if let fiveHourDisplayPercent {
            text = "5h \(Int(fiveHourDisplayPercent))% · 7d \(Int(weeklyDisplayPercent))%"
        } else {
            text = "7d \(Int(weeklyDisplayPercent))%"
        }
        return StatusBarQuotaState(
            text: text,
            fiveHourDisplayPercent: fiveHourDisplayPercent,
            fiveHourUsedPercent: active.hasFiveHourQuota ? active.fiveHourUsedPercent : nil,
            weeklyDisplayPercent: weeklyDisplayPercent,
            weeklyUsedPercent: active.weeklyUsedPercent
        )
    }

    private static func iconName(from store: TokenStore) -> String {
        let ref: [TokenAccount]
        if let active = store.accounts.first(where: { $0.isActive }) {
            ref = [active]
        } else {
            ref = store.accounts
        }
        if ref.contains(where: { $0.isBanned }) {
            return "xmark.circle.fill"
        }
        if ref.contains(where: { $0.weeklyExhausted }) {
            return "exclamationmark.triangle.fill"
        }
        if ref.contains(where: {
            $0.fiveHourExhausted ||
                ($0.hasFiveHourQuota && ($0.fiveHourUsedPercent ?? 0) >= 80) ||
                $0.weeklyUsedPercent >= 80
        }) {
            return "bolt.circle.fill"
        }
        return "codexappbar"
    }

    private static func taskStatusToolTip(
        snapshot: TaskCenterSnapshot,
        hookState: CodexHookInstallState
    ) -> String {
        guard !hookState.needsAction else { return L.codexHookTooltipNeedsInstall }
        let summary = L.taskStatusSummary(
            needsAttention: snapshot.needsAttentionCount,
            running: snapshot.runningCount
        )
        guard let record = snapshot.mostUrgent else { return summary }
        return "\(summary) · \(record.projectName) · \(L.taskStatusPhase(record.phase))"
    }
}

private struct StatusBarQuotaState {
    let text: String
    let fiveHourDisplayPercent: Double?
    let fiveHourUsedPercent: Double?
    let weeklyDisplayPercent: Double?
    let weeklyUsedPercent: Double?

    static let empty = StatusBarQuotaState(
        text: "7d --",
        fiveHourDisplayPercent: nil,
        fiveHourUsedPercent: nil,
        weeklyDisplayPercent: nil,
        weeklyUsedPercent: nil
    )

    var hasBars: Bool {
        weeklyDisplayPercent != nil
    }

    var showsFiveHourQuota: Bool {
        fiveHourDisplayPercent != nil && fiveHourUsedPercent != nil
    }
}

private final class FirstMouseHostingController<Content: View>: NSViewController {
    private let rootView: Content
    private let onSizeChange: (() -> Void)?

    init(rootView: Content, onSizeChange: (() -> Void)? = nil) {
        self.rootView = rootView
        self.onSizeChange = onSizeChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let hosting = FirstMouseHostingView(rootView: rootView)
        // Minimum constraints keep the glass host aligned during first layout;
        // this fixed-width popup does not need a maximum-size proposal.
        hosting.sizingOptions = [.minSize, .intrinsicContentSize]
        hosting.onSizeChange = onSizeChange
        view = hosting
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: (() -> Void)?
    private var sizeCheckQueued = false
    private var lastReportedSize: NSSize?
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        guard onSizeChange != nil, !sizeCheckQueued else { return }
        sizeCheckQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Keep the flag set while measuring: SwiftUI may invalidate again
            // during the measurement itself.
            let size = self.intrinsicContentSize
            if size != self.lastReportedSize {
                self.lastReportedSize = size
                self.onSizeChange?()
            }
            self.sizeCheckQueued = false
        }
    }
    // SwiftUI can return nil for glass, spacers and disabled controls. Keep
    // those clicks inside the visible panel while leaving its shadow/corners out.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let panel = window as? MenuBarGlassPanel else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        let topDown = NSPoint(x: local.x - bounds.minX,
                              y: isFlipped ? local.y - bounds.minY : bounds.maxY - local.y)
        guard panel.contentHitPath(in: bounds.size).contains(topDown) else { return nil }
        return super.hitTest(point) ?? self
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private final class StatusBarCapsuleView: NSView {
    private static let leftPadding: CGFloat = 0
    private static let rightPadding: CGFloat = 2
    private static let iconSize: CGFloat = 16
    private static let textGap: CGFloat = 3
    private static let barsGap: CGFloat = 4
    private static let lightGap: CGFloat = 8
    private static let textRenderPadding: CGFloat = 4
    private static let textFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    private static let textAttributes: [NSAttributedString.Key: Any] = [
        .font: textFont,
        .foregroundColor: NSColor.white.withAlphaComponent(0.93)
    ]

    private let iconView = NSImageView()
    private let textField = NSTextField(labelWithString: "")
    private let barsView = StatusQuotaBarsView()
    private let lightsView = StatusTaskCountsView()
    private var snapshot: TaskCenterSnapshot = .empty
    private var quotaState = StatusBarQuotaState.empty
    private var showStatusLights = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    static func width(for quotaState: StatusBarQuotaState, showStatusLights: Bool, snapshot: TaskCenterSnapshot) -> CGFloat {
        let contentWidth = contentWidth(for: quotaState)
        let contentGap = quotaState.hasBars ? barsGap : textGap
        let countsWidth = StatusTaskCountsView.width(for: snapshot)
        let statusLightsWidth = showStatusLights && countsWidth > 0 ? lightGap + countsWidth : 0
        return leftPadding + iconSize + contentGap + contentWidth + statusLightsWidth + rightPadding
    }

    func configure(
        iconName: String,
        quotaState: StatusBarQuotaState,
        light: CodexSessionLight,
        snapshot: TaskCenterSnapshot,
        showStatusLights: Bool
    ) {
        iconView.image = Self.statusIcon(systemName: iconName)
        self.quotaState = quotaState
        self.showStatusLights = showStatusLights
        if textField.stringValue != quotaState.text {
            textField.stringValue = quotaState.text
        }
        barsView.configure(
            fiveHourDisplayPercent: quotaState.fiveHourDisplayPercent,
            fiveHourUsedPercent: quotaState.fiveHourUsedPercent,
            weeklyDisplayPercent: quotaState.weeklyDisplayPercent ?? 0,
            weeklyUsedPercent: quotaState.weeklyUsedPercent ?? 0
        )
        self.snapshot = snapshot
        lightsView.isHidden = !showStatusLights || StatusTaskCountsView.width(for: snapshot) == 0
        lightsView.configure(snapshot: snapshot, available: light != .offline)
        needsLayout = true
    }

    override func layout() {
        super.layout()

        let textSize = (textField.stringValue as NSString).size(withAttributes: Self.textAttributes)
        let useBars = quotaState.hasBars
        let contentGap = useBars ? Self.barsGap : Self.textGap
        let contentWidth = Self.contentWidth(for: quotaState)
        let iconRect = NSRect(
            x: Self.leftPadding,
            y: (bounds.height - Self.iconSize) / 2,
            width: Self.iconSize,
            height: Self.iconSize
        )
        iconView.frame = iconRect

        let contentX = iconRect.maxX + contentGap
        if useBars {
            textField.isHidden = true
            barsView.isHidden = false
            barsView.frame = NSRect(
                x: contentX,
                y: 0,
                width: contentWidth,
                height: bounds.height
            )
        } else {
            barsView.isHidden = true
            textField.isHidden = false
            textField.frame = NSRect(
                x: contentX,
                y: (bounds.height - textSize.height) / 2 - 0.3,
                width: contentWidth,
                height: textSize.height + 1
            )
        }

        if showStatusLights && StatusTaskCountsView.width(for: snapshot) > 0 {
            lightsView.isHidden = false
            lightsView.frame = NSRect(
                x: contentX + contentWidth + Self.lightGap,
                y: 0,
                width: StatusTaskCountsView.width(for: snapshot),
                height: bounds.height
            )
        } else {
            lightsView.isHidden = true
            lightsView.frame = .zero
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(iconView)

        textField.font = Self.textFont
        textField.textColor = NSColor.white.withAlphaComponent(0.93)
        textField.backgroundColor = .clear
        textField.isBezeled = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.drawsBackground = false
        textField.translatesAutoresizingMaskIntoConstraints = true
        addSubview(textField)

        barsView.translatesAutoresizingMaskIntoConstraints = true
        barsView.isHidden = true
        addSubview(barsView)

        lightsView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(lightsView)
    }

    private static func contentWidth(for quotaState: StatusBarQuotaState) -> CGFloat {
        if quotaState.hasBars {
            return StatusQuotaBarsView.contentWidth(for: quotaState)
        }
        return measuredTextWidth(for: quotaState.text)
    }

    private static func measuredTextWidth(for text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: textAttributes).width) + textRenderPadding
    }

    private static func statusIcon(systemName: String) -> NSImage? {
        if systemName == "codexappbar" { return CodexBrandMark.menuImage }
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: NSColor.white.withAlphaComponent(0.93)))
        return NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }
}

private final class StatusQuotaBarsView: NSView {
    private struct Metrics {
        let itemGap: CGFloat
        let trackWidth: CGFloat
        let trackHeight: CGFloat
        let labelFont: NSFont
        let valueFont: NSFont
        let rowCenterGap: CGFloat
        let labelAlpha: CGFloat
        let valueAlpha: CGFloat
    }

    private static let singleMetrics = Metrics(
        itemGap: 4,
        trackWidth: 44,
        trackHeight: 5.2,
        labelFont: .monospacedDigitSystemFont(ofSize: 10, weight: .regular),
        valueFont: .monospacedDigitSystemFont(ofSize: 11, weight: .regular),
        rowCenterGap: 0,
        labelAlpha: 0.9,
        valueAlpha: 0.98
    )
    private static let dualMetrics = Metrics(
        itemGap: 3,
        trackWidth: 44,
        trackHeight: 3.2,
        labelFont: .monospacedDigitSystemFont(ofSize: 7.5, weight: .medium),
        valueFont: .monospacedDigitSystemFont(ofSize: 8, weight: .semibold),
        rowCenterGap: 8.2,
        labelAlpha: 0.76,
        valueAlpha: 0.92
    )
    private static let labelTextYOffset: CGFloat = -0.2
    private static let valueTextYOffset: CGFloat = -0.2
    private static let fillAnimationKey = "codexbar.quotaFill"
    private static let fillAnimationDuration: CFTimeInterval = 0.38

    private struct RowLayout {
        let labelRect: NSRect
        let trackRect: NSRect
        let valueRect: NSRect
    }

    private let fiveHourFillLayer = CAShapeLayer()
    private let weeklyFillLayer = CAShapeLayer()
    private var fiveHourDisplayPercent: Double?
    private var fiveHourUsedPercent: Double?
    private var weeklyDisplayPercent: Double = 0
    private var weeklyUsedPercent: Double = 0
    private var hasLaidOutFillLayers = false
    private var lastFillBounds: NSRect = .zero

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupFillLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupFillLayers()
    }

    func configure(
        fiveHourDisplayPercent: Double?,
        fiveHourUsedPercent: Double?,
        weeklyDisplayPercent: Double,
        weeklyUsedPercent: Double
    ) {
        let nextFiveHourDisplay = fiveHourDisplayPercent.map(Self.clamped)
        let nextFiveHourUsed = fiveHourUsedPercent.map(Self.clamped)
        let normalizedFiveHourDisplay = nextFiveHourDisplay != nil && nextFiveHourUsed != nil
            ? nextFiveHourDisplay
            : nil
        let normalizedFiveHourUsed = nextFiveHourDisplay != nil && nextFiveHourUsed != nil
            ? nextFiveHourUsed
            : nil
        let nextWeeklyDisplay = Self.clamped(weeklyDisplayPercent)
        let nextWeeklyUsed = Self.clamped(weeklyUsedPercent)
        let displayChanged = self.fiveHourDisplayPercent != normalizedFiveHourDisplay ||
            self.weeklyDisplayPercent != nextWeeklyDisplay
        guard self.fiveHourDisplayPercent != normalizedFiveHourDisplay ||
            self.fiveHourUsedPercent != normalizedFiveHourUsed ||
            self.weeklyDisplayPercent != nextWeeklyDisplay ||
            self.weeklyUsedPercent != nextWeeklyUsed else { return }
        let fiveHourFromPath = fiveHourFillLayer.presentation()?.path ?? fiveHourFillLayer.path
        let weeklyFromPath = weeklyFillLayer.presentation()?.path ?? weeklyFillLayer.path
        self.fiveHourDisplayPercent = normalizedFiveHourDisplay
        self.fiveHourUsedPercent = normalizedFiveHourUsed
        self.weeklyDisplayPercent = nextWeeklyDisplay
        self.weeklyUsedPercent = nextWeeklyUsed
        updateFillLayers(
            animated: displayChanged && hasLaidOutFillLayers && window != nil && !isHidden,
            fiveHourFromPath: fiveHourFromPath,
            weeklyFromPath: weeklyFromPath
        )
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if !hasLaidOutFillLayers || !NSEqualRects(lastFillBounds, bounds) {
            updateFillLayers(animated: false)
            lastFillBounds = bounds
        }
        hasLaidOutFillLayers = true
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let fiveHourDisplayPercent, showsFiveHourQuota {
            let rowOffset = Self.dualMetrics.rowCenterGap / 2
            drawRow(
                label: "5h",
                displayPercent: fiveHourDisplayPercent,
                centerY: bounds.midY + rowOffset,
                metrics: Self.dualMetrics
            )
            drawRow(
                label: "7d",
                displayPercent: weeklyDisplayPercent,
                centerY: bounds.midY - rowOffset,
                metrics: Self.dualMetrics
            )
        } else {
            drawRow(
                label: "7d",
                displayPercent: weeklyDisplayPercent,
                centerY: bounds.midY,
                metrics: Self.singleMetrics
            )
        }
    }

    private func drawRow(
        label: String,
        displayPercent: Double,
        centerY: CGFloat,
        metrics: Metrics
    ) {
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: metrics.labelFont,
            .foregroundColor: NSColor.white.withAlphaComponent(metrics.labelAlpha)
        ]
        let value = Self.valueText(for: displayPercent)
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: metrics.valueFont,
            .foregroundColor: NSColor.white.withAlphaComponent(metrics.valueAlpha)
        ]
        let rowLayout = layoutRow(
            label: label,
            value: value,
            centerY: centerY,
            metrics: metrics
        )

        (label as NSString).draw(in: rowLayout.labelRect, withAttributes: labelAttributes)
        drawPill(
            rowLayout.trackRect,
            radius: metrics.trackHeight / 2,
            color: NSColor.white.withAlphaComponent(0.18)
        )
        (value as NSString).draw(in: rowLayout.valueRect, withAttributes: valueAttributes)
    }

    private func setupFillLayers() {
        wantsLayer = true
        layer?.masksToBounds = false

        [fiveHourFillLayer, weeklyFillLayer].forEach { fillLayer in
            fillLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            fillLayer.masksToBounds = false
            fillLayer.opacity = 0
            fillLayer.zPosition = 1
            layer?.addSublayer(fillLayer)
        }
    }

    private func drawPill(_ rect: NSRect, radius: CGFloat, color: NSColor) {
        color.setFill()
        NSBezierPath(
            roundedRect: rect,
            xRadius: radius,
            yRadius: radius
        ).fill()
    }

    private func updateFillLayers(
        animated: Bool,
        fiveHourFromPath: CGPath? = nil,
        weeklyFromPath: CGPath? = nil
    ) {
        guard bounds.width > 0 else { return }
        let metrics = showsFiveHourQuota ? Self.dualMetrics : Self.singleMetrics
        let rowOffset = metrics.rowCenterGap / 2
        if let fiveHourDisplayPercent, let fiveHourUsedPercent, showsFiveHourQuota {
            updateFillLayer(
                fiveHourFillLayer,
                label: "5h",
                displayPercent: fiveHourDisplayPercent,
                usedPercent: fiveHourUsedPercent,
                centerY: bounds.midY + rowOffset,
                metrics: metrics,
                animated: animated,
                fromPath: fiveHourFromPath
            )
        } else {
            hideFillLayer(fiveHourFillLayer)
        }
        updateFillLayer(
            weeklyFillLayer,
            label: "7d",
            displayPercent: weeklyDisplayPercent,
            usedPercent: weeklyUsedPercent,
            centerY: bounds.midY - rowOffset,
            metrics: metrics,
            animated: animated,
            fromPath: weeklyFromPath
        )
    }

    private func updateFillLayer(
        _ fillLayer: CAShapeLayer,
        label: String,
        displayPercent: Double,
        usedPercent: Double,
        centerY: CGFloat,
        metrics: Metrics,
        animated: Bool,
        fromPath: CGPath?
    ) {
        let newPath = fillPath(
            label: label,
            displayPercent: displayPercent,
            centerY: centerY,
            metrics: metrics
        )
        let newOpacity: Float = displayPercent > 0 ? 1 : 0
        let oldPath = fromPath ?? fillLayer.presentation()?.path ?? fillLayer.path ?? newPath
        let oldOpacity = fillLayer.presentation()?.opacity ?? fillLayer.opacity

        fillLayer.removeAnimation(forKey: Self.fillAnimationKey)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.frame = bounds
        fillLayer.fillColor = Self.color(forUsedPercent: usedPercent).cgColor
        fillLayer.path = newPath
        fillLayer.opacity = newOpacity
        CATransaction.commit()

        guard animated else { return }

        let pathAnimation = CABasicAnimation(keyPath: "path")
        pathAnimation.fromValue = oldPath
        pathAnimation.toValue = newPath

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = oldOpacity
        opacityAnimation.toValue = newOpacity

        let group = CAAnimationGroup()
        group.animations = [pathAnimation, opacityAnimation]
        group.duration = Self.fillAnimationDuration
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        group.isRemovedOnCompletion = true
        fillLayer.add(group, forKey: Self.fillAnimationKey)
    }

    private func hideFillLayer(_ fillLayer: CAShapeLayer) {
        fillLayer.removeAnimation(forKey: Self.fillAnimationKey)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.opacity = 0
        CATransaction.commit()
    }

    private func fillPath(
        label: String,
        displayPercent: Double,
        centerY: CGFloat,
        metrics: Metrics
    ) -> CGPath {
        let trackRect = layoutRow(
            label: label,
            value: Self.valueText(for: displayPercent),
            centerY: centerY,
            metrics: metrics
        ).trackRect
        let fillWidth: CGFloat
        if displayPercent > 0 {
            fillWidth = max(metrics.trackHeight, trackRect.width * CGFloat(displayPercent) / 100)
        } else {
            fillWidth = metrics.trackHeight
        }
        let fillRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: fillWidth,
            height: trackRect.height
        )
        return CGPath(
            roundedRect: fillRect,
            cornerWidth: metrics.trackHeight / 2,
            cornerHeight: metrics.trackHeight / 2,
            transform: nil
        )
    }

    private func layoutRow(
        label: String,
        value: String,
        centerY: CGFloat,
        metrics: Metrics
    ) -> RowLayout {
        let labelSize = Self.textSize(label, font: metrics.labelFont)
        let valueSize = Self.textSize(value, font: metrics.valueFont)
        // Keep both dual-quota rows on the same columns. Otherwise `100%` makes
        // the first row wider than `99%`, and centering each row independently
        // shifts the second row's track to the right.
        let labelColumnWidth = Self.columnWidth(
            labels: showsFiveHourQuota ? ["5h", "7d"] : [label],
            font: metrics.labelFont
        )
        let valueColumnWidth = Self.columnWidth(labels: ["100%"], font: metrics.valueFont)
        let contentWidth = labelColumnWidth + metrics.itemGap + metrics.trackWidth +
            metrics.itemGap + valueColumnWidth
        let leadingInset = max((bounds.width - contentWidth) / 2, 0)
        let labelRect = NSRect(
            x: leadingInset,
            y: centerY - labelSize.height / 2 + Self.labelTextYOffset,
            width: labelSize.width,
            height: labelSize.height
        )
        let trackRect = NSRect(
            x: leadingInset + labelColumnWidth + metrics.itemGap,
            y: centerY - metrics.trackHeight / 2,
            width: metrics.trackWidth,
            height: metrics.trackHeight
        )
        let valueRect = NSRect(
            x: trackRect.maxX + metrics.itemGap,
            y: centerY - valueSize.height / 2 + Self.valueTextYOffset,
            width: valueSize.width,
            height: valueSize.height
        )
        return RowLayout(labelRect: labelRect, trackRect: trackRect, valueRect: valueRect)
    }

    private var showsFiveHourQuota: Bool {
        fiveHourDisplayPercent != nil && fiveHourUsedPercent != nil
    }

    static func contentWidth(for quotaState: StatusBarQuotaState) -> CGFloat {
        let metrics = quotaState.showsFiveHourQuota ? dualMetrics : singleMetrics
        let labels = quotaState.showsFiveHourQuota ? ["5h", "7d"] : ["7d"]
        let values = quotaState.showsFiveHourQuota
            ? [quotaState.fiveHourDisplayPercent ?? 0, quotaState.weeklyDisplayPercent ?? 0]
            : [quotaState.weeklyDisplayPercent ?? 0]
        let valueTexts = values.map { valueText(for: $0) }

        // Size the outer capsule from the values that are actually visible so
        // the status lights keep a tight, consistent gap after the percentages.
        return columnWidth(labels: labels, font: metrics.labelFont) + metrics.itemGap +
            metrics.trackWidth + metrics.itemGap +
            columnWidth(labels: valueTexts, font: metrics.valueFont)
    }

    private static func columnWidth(labels: [String], font: NSFont) -> CGFloat {
        labels.reduce(0) { width, label in
            max(width, ceil(textSize(label, font: font).width))
        }
    }

    private static func textSize(_ text: String, font: NSFont) -> NSSize {
        (text as NSString).size(withAttributes: [.font: font])
    }

    private static func valueText(for displayPercent: Double) -> String {
        "\(Int(clamped(displayPercent)))%"
    }

    private static func color(forUsedPercent usedPercent: Double) -> NSColor {
        CodexStatusPalette.menuBarColor(forUsedPercent: usedPercent)
    }

    nonisolated private static func clamped(_ percent: Double) -> Double {
        min(max(percent, 0), 100)
    }
}

/// Simultaneous task counts preserve every state, including when attention and running coexist.
final class StatusTaskCountsView: NSView {
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    private let labels = (0..<3).map { _ in NSTextField(labelWithString: "0") }
    private let icons = (0..<3).map { _ in NSImageView() }
    private let separator = CALayer()
    private static let leadingInset: CGFloat = 8
    private static let symbolWidth: CGFloat = 11
    private static let iconTextGap: CGFloat = 1
    private static let groupGap: CGFloat = 6
    // NSTextField includes two points of text inset on each side.
    private static let labelInsets: CGFloat = 4
    private var ringRect: CGRect = .zero
    private var ringColor = CodexStatusPalette.runningNSColor
    private let ringHost = CALayer()
    private let rotatingRing = CALayer()
    private let ringTrack = CAShapeLayer()
    private var ringSegments: [CAShapeLayer] = []
    private static let rotationKey = "codexbar.status-ring.rotation"
    private var counts = [0, 0, 0]
    private var available = false
    private var motionObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for view in labels {
            view.font = Self.font
            view.drawsBackground = false
            view.isBezeled = false
            view.isSelectable = false
            addSubview(view)
        }
        for (index, icon) in icons.enumerated() {
            if index == 0 {
                icon.image = NSImage(systemSymbolName: "exclamationmark", accessibilityDescription: nil)
                icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            }
            icon.imageScaling = .scaleProportionallyUpOrDown
            addSubview(icon)
        }
        separator.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        layer?.addSublayer(separator)
        ringHost.name = "status-ring-host"
        rotatingRing.name = "status-ring-rotation"
        layer?.addSublayer(ringHost)
        ringHost.addSublayer(ringTrack)
        ringHost.addSublayer(rotatingRing)
        ringTrack.path = CGPath(ellipseIn: CGRect(x: 1, y: 1, width: 9, height: 9), transform: nil)
        ringTrack.fillColor = nil
        ringTrack.lineWidth = 1.5
        for segment in 0..<36 {
            let arc = CAShapeLayer()
            let angle = CGFloat(30) - CGFloat(segment) * 7.8
            let path = CGMutablePath()
            path.addArc(center: CGPoint(x: 5.5, y: 5.5), radius: 4.5,
                        startAngle: angle * .pi / 180, endAngle: (angle - 8) * .pi / 180, clockwise: true)
            arc.path = path
            arc.fillColor = nil
            arc.lineWidth = 1.7
            arc.lineCap = .round
            rotatingRing.addSublayer(arc)
            ringSegments.append(arc)
        }
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateAnimation() }
    }
    required init?(coder: NSCoder) { nil }
    deinit { if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) } }

    static func width(for snapshot: TaskCenterSnapshot) -> CGFloat {
        let counts = [snapshot.needsAttentionCount, snapshot.runningCount, snapshot.readyCount].filter { $0 > 0 }
        guard !counts.isEmpty else { return 0 }
        return counts.reduce(leadingInset) { $0 + groupWidth($1) } - groupGap
    }
    private static func groupWidth(_ count: Int) -> CGFloat {
        symbolWidth + iconTextGap + ceil((String(count) as NSString).size(withAttributes: [.font: font]).width) + labelInsets + groupGap
    }
    func configure(snapshot: TaskCenterSnapshot, available: Bool) {
        counts = [snapshot.needsAttentionCount, snapshot.runningCount, snapshot.readyCount]
        self.available = available
        let colors: [NSColor] = [.systemRed, CodexStatusPalette.runningNSColor, .systemGreen]
        for index in 0..<3 {
            labels[index].stringValue = String(counts[index])
            labels[index].isHidden = counts[index] == 0
            icons[index].isHidden = labels[index].isHidden
            let color = available && counts[index] > 0 ? colors[index] : NSColor.white.withAlphaComponent(0.45)
            labels[index].textColor = color
            icons[index].contentTintColor = color
            if index == 1 { ringColor = color }
        }
        setAccessibilityElement(true)
        setAccessibilityLabel(L.zh
            ? "\(counts[0]) 个需处理，\(counts[1]) 个进行中，\(counts[2]) 个待查看"
            : "\(counts[0]) need attention, \(counts[1]) running, \(counts[2]) unread")
        needsLayout = true
        needsDisplay = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringTrack.strokeColor = ringColor.withAlphaComponent(0.13).cgColor
        for (index, segment) in ringSegments.enumerated() {
            let progress = CGFloat(index) / 35
            segment.strokeColor = ringColor.withAlphaComponent(0.08 + 0.92 * progress * progress).cgColor
        }
        CATransaction.commit()
        updateAnimation()
    }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        separator.isHidden = !counts.contains { $0 > 0 }
        separator.frame = CGRect(x: 0, y: (bounds.height - 10) / 2, width: 0.5, height: 10)
        CATransaction.commit()
        var x = Self.leadingInset
        ringRect = .zero
        for index in 0..<3 {
            guard counts[index] > 0 else {
                labels[index].frame = .zero
                icons[index].frame = .zero
                continue
            }
            let width = Self.groupWidth(counts[index])
            icons[index].frame = NSRect(x: x, y: (bounds.height - Self.symbolWidth) / 2,
                                       width: Self.symbolWidth, height: Self.symbolWidth)
            let labelHeight = ceil(labels[index].fittingSize.height)
            labels[index].frame = NSRect(x: x + Self.symbolWidth + Self.iconTextGap,
                y: (bounds.height - labelHeight) / 2,
                width: width - Self.symbolWidth - Self.iconTextGap - Self.groupGap, height: labelHeight)
            if index == 1 {
                ringRect = NSRect(x: x + 1, y: (bounds.height - 9) / 2, width: 9, height: 9)
            }
            x += width
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringHost.isHidden = ringRect.isEmpty
        ringHost.bounds = CGRect(x: 0, y: 0, width: 11, height: 11)
        ringHost.position = CGPoint(x: ringRect.midX, y: ringRect.midY)
        // Never set frame on the rotating layer: its transformed frame changes
        // during rotation and would distort the icon during status-item layout.
        rotatingRing.bounds = ringHost.bounds
        rotatingRing.position = CGPoint(x: 5.5, y: 5.5)
        CATransaction.commit()
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard counts[2] > 0 else { return }
        // Draw at the same optical scale as the activity ring, avoiding the
        // narrow proportions of a scaled SF Symbol in this small status item.
        let checkFrame = icons[2].frame
        let check = NSBezierPath()
        check.lineWidth = 1.8
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.move(to: NSPoint(x: checkFrame.minX + 1, y: checkFrame.midY))
        check.line(to: NSPoint(x: checkFrame.minX + 4, y: checkFrame.midY - 3))
        check.line(to: NSPoint(x: checkFrame.maxX - 1, y: checkFrame.midY + 3.5))
        (icons[2].contentTintColor ?? .systemGreen).setStroke()
        check.stroke()
    }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateAnimation() }
    private func updateAnimation() {
        guard window != nil, !isHidden, available, counts[1] > 0,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            rotatingRing.removeAnimation(forKey: Self.rotationKey)
            return
        }
        guard rotatingRing.animation(forKey: Self.rotationKey) == nil else { return }
        // Core Animation advances in the compositor while AppKit builds/tracks
        // the popup; a main-run-loop timer cannot keep drawing through that work.
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = -2 * Double.pi
        animation.duration = 1.4
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        rotatingRing.add(animation, forKey: Self.rotationKey)
    }
}
