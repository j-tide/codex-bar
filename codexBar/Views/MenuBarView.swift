import SwiftUI
import AppKit
import UserNotifications
import Combine
import UniformTypeIdentifiers

enum PopupSpacing {
    static let compact: CGFloat = 4
    static let regular: CGFloat = 8
    static let section: CGFloat = 12
    static let block: CGFloat = 16
}

struct MenuBarView: View {
    @Environment(\.popupArrowX) private var popupArrowX
    var liveUpdates = true
    var onAppearanceChange: (String) -> Void = { _ in }
    var onOpenNotificationSettings: (@escaping (Bool) -> Void) -> Void = { completion in completion(false) }
    @AppStorage("popupAppearance") private var popupAppearance = "system"
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var preferredScheme: ColorScheme? {
        popupAppearance == "dark" ? .dark : popupAppearance == "light" ? .light : nil
    }
    private var usesDarkAppearance: Bool { (preferredScheme ?? systemColorScheme) == .dark }
    @EnvironmentObject var store: TokenStore
    @EnvironmentObject var oauth: OAuthManager
    @EnvironmentObject var language: LanguageSettings
    @EnvironmentObject var refreshFrequency: RefreshFrequencySettings
    @EnvironmentObject var quotaDisplay: QuotaDisplaySettings
    @EnvironmentObject var taskCenter: TaskCenterService
    @EnvironmentObject var codexHookInstaller: CodexHookInstallerService
    @EnvironmentObject var appUpdater: AppUpdateService
    @ObservedObject private var radar = CodexRadarService.shared
    @State private var isRefreshing = false
    @State private var showError: String?
    @State private var showSuccess: String?
    @State private var now = Date()
    @State private var refreshingAccounts: Set<String> = []
    @State private var lastVisibleRefresh = Date()

    // 每秒刷新相对时间显示，并按用户选择的频率决定是否拉取额度。
    private let tickTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var menuVisible = false
    @Namespace private var languageSelection

    private var backupAccounts: [TokenAccount] {
        store.accounts.filter { !$0.isActive }.sorted {
            if $0.isAvailable != $1.isAvailable { return $0.isAvailable }
            if $0.tokenExpired != $1.tokenExpired { return !$0.tokenExpired }
            if $0.weeklyUsedPercent != $1.weeklyUsedPercent { return $0.weeklyUsedPercent < $1.weeklyUsedPercent }
            return $0.id < $1.id
        }
    }

    private var taskSectionHeight: CGFloat {
        let rows = min(taskCenter.displayRecords.count, 6)
        let notices: CGFloat = (codexHookInstaller.state.needsAction ? 56 : 0)
            + (taskCenter.snapshot.unreadableCount > 0 ? 24 : 0)
        return min(PopupLayout.activityHeight, max(160, 60 + CGFloat(rows) * 48 + notices))
    }

    private var accountSectionHeight: CGFloat {
        min(PopupLayout.activityHeight, store.accounts.count >= 3 ? 336 : store.accounts.count == 2 ? 280 : 190)
    }

    private var contentHeight: CGFloat {
        max(taskSectionHeight, accountSectionHeight) + insightsHeight + 1
    }

    private var insightsHeight: CGFloat {
        let rows = CodexRadarPresentation.matrix(from: radar.intelligence?.modelIQ(for: .comprehensive)).rows.count
        // Include the radar header, footer, spacing and outer padding.
        return max(252, CodexRadarTableView.height(rowCount: rows) + 96)
    }

    private var availableCount: Int { store.accounts.filter(\.isAvailable).count }

    private var refreshHelpText: String {
        if let lastUpdate = store.accounts.compactMap({ $0.lastChecked }).max() {
            return "\(L.refreshUsage) · \(relativeTime(lastUpdate))"
        }
        return L.refreshUsage
    }

    var body: some View {
        PopupGlassGroup { panel }
            // Glass may leave zero-alpha areas in the host backing store. A
            // minimal contour fill gives WindowServer a continuous input surface.
            .background { PopupGlassOutline(arrowX: popupArrowX).fill(.black.opacity(0.01)) }
            .contentShape(.interaction, PopupGlassOutline(arrowX: popupArrowX))
            .popupThemeWave(dark: usesDarkAppearance)
            .overlay {
                PopupGlassOutline(arrowX: popupArrowX)
                    .stroke(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08), .black.opacity(0.12), .white.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            // Clip after the glass container has composited its surfaces.
            .clipShape(PopupGlassOutline(arrowX: popupArrowX))
            .shadow(color: .black.opacity(usesDarkAppearance ? 0.38 : 0.22), radius: 10, x: 0, y: 4)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if appUpdater.completedUpdate != nil || appUpdater.shouldShowUpdateRow {
                VStack(spacing: 8) {
                    if let completion = appUpdater.completedUpdate {
                        AppUpdateCompletedRow(completion: completion) { appUpdater.dismissCompletedUpdate() }
                    }
                    if appUpdater.shouldShowUpdateRow { AppUpdateRow(updater: appUpdater) }
                }
                .padding(.horizontal, PopupSpacing.section)
                .padding(.vertical, PopupSpacing.regular)
            }
            Divider()
                .overlay { HeaderRefreshSweep(isRefreshing: isRefreshing) }
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    TaskActivityListView(
                        onOpenNotificationSettings: onOpenNotificationSettings,
                        onInstallHooks: installCodexHooks
                    )
                    .popupEntrance()
                    .frame(maxHeight: .infinity)
                    Divider()
                    CodexRadarView().popupEntrance(delay: 0.08)
                        .frame(height: insightsHeight, alignment: .top)
                }
                .frame(width: PopupLayout.columnWidth)
                Divider().frame(width: 1)
                VStack(spacing: 0) {
                    accountSection.popupEntrance(delay: 0.04)
                        .frame(maxHeight: .infinity)
                    Divider()
                    TokenStatsView().popupEntrance(delay: 0.12)
                        .frame(height: insightsHeight)
                }
                .frame(width: PopupLayout.columnWidth)
            }
            .frame(height: contentHeight)

            if let success = showSuccess {
                Divider()
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(success)
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal, PopupSpacing.section)
                .padding(.vertical, PopupSpacing.regular)
            }

            if let error = showError {
                Divider()
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text(error)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        showError = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                }
                .padding(.horizontal, PopupSpacing.section)
                .padding(.vertical, PopupSpacing.regular)
            }

            Divider()

            // 底部操作栏
            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: PopupSpacing.regular) {
                    Button {
                        showError = nil
                        oauth.startOAuth { result in
                            switch result {
                            case .success(let tokens):
                                let account = AccountBuilder.build(from: tokens)
                                do {
                                    let key = try store.commitOAuthAccount(account)
                                    Task { await WhamService.shared.refreshOne(key: key, store: store, forceSubscriptionRefresh: true) }
                                } catch {
                                    showError = error.localizedDescription
                                }
                            case .failure(let error):
                                if case OAuthError.cancelled = error { break }
                                showError = error.localizedDescription
                            }
                    }
                } label: {
                    Label(oauth.isAuthorizing ? (L.zh ? "重新授权" : "Restart sign-in") : (L.zh ? "添加" : "Add"), systemImage: "person.badge.key")
                        .font(.system(size: 12))
                        .frame(height: 18, alignment: .center)
                }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .help(oauth.isAuthorizing ? (L.zh ? "结束上一轮授权并打开新的授权网页" : "End the previous attempt and open a new sign-in page") : L.addAccount)

                    if oauth.isAuthorizing {
                        Button {
                            oauth.cancelOAuth()
                            showError = nil
                        } label: {
                            Label(L.zh ? "取消授权" : "Cancel sign-in", systemImage: "xmark.circle")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless).focusable(false)
                        .help(L.zh ? "关闭授权网页后，可在这里取消等待" : "Cancel the pending attempt after closing the browser page")
                    }

                    Button {
                        importAccounts()
                    } label: {
                        Label(L.zh ? "导入" : "Import", systemImage: "doc.badge.plus")
                            .font(.system(size: 12))
                            .frame(height: 18, alignment: .center)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .help(L.importAccount)
                }

                Divider().frame(height: 14).padding(.horizontal, 12)
                HStack(spacing: 0) {
                    ForEach(["zh", "en"], id: \.self) { code in
                        let selected = language.identity == code
                        Button { language.selectChinese(code == "zh") } label: {
                            Text(code == "zh" ? "中" : "EN")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(selected ? PopupLayout.accent : Color.secondary)
                                .frame(width: 32, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).focusable(false).focusEffectDisabled()
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: PopupControlMetrics.selectionRadius)
                                    .fill(PopupLayout.accent.opacity(0.16))
                                    .matchedGeometryEffect(id: "language", in: languageSelection)
                            }
                        }
                        .accessibilityLabel(code == "zh" ? "中文" : "English")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .help(code == "zh" ? "切换为中文" : "Switch to English")
                    }
                }
                .padding(3).popupGlass()
                .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85), value: language.identity)

                Spacer(minLength: PopupSpacing.regular)

                HStack(spacing: PopupSpacing.regular) {
                    Button {
                        refreshFrequency.cycle()
                        lastVisibleRefresh = .distantPast
                    } label: {
                        HStack(alignment: .center, spacing: 2) {
                            Image(systemName: "timer")
                                .font(.system(size: 11))
                            Text(refreshFrequency.buttonLabel)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .frame(height: 18, alignment: .center)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .help(refreshFrequency.helpText)

                    Button {
                        quotaDisplay.toggleAmountMode()
                    } label: {
                        Text(quotaDisplay.amountMode.shortLabel)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(height: 18, alignment: .center)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .help(quotaDisplay.amountHelpText)

                    Button {
                        quotaDisplay.toggleStatusLights()
                    } label: {
                        StatusLightsToggleIcon(isOn: quotaDisplay.showStatusLights)
                            .frame(width: 22, height: 18, alignment: .center)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .help(quotaDisplay.statusLightsHelpText)

                }
                .padding(.horizontal, PopupSpacing.regular)
                .padding(.vertical, PopupSpacing.compact)
                .popupGlass()

                Spacer().frame(width: 12)

                HStack(spacing: PopupSpacing.regular) {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
                            popupAppearance = usesDarkAppearance ? "light" : "dark"
                        }
                    } label: {
                        Image(systemName: usesDarkAppearance ? "sun.max" : "moon")
                            .font(.system(size: 12)).frame(width: 18, height: 18)
                            .contentTransition(.symbolEffect(.replace))
                            .rotation3DEffect(.degrees(reduceMotion ? 0 : usesDarkAppearance ? -180 : 0), axis: (x: 0, y: 1, z: 0))
                    }
                    .popupGlassButton(iconOnly: true)
                    .anchorPreference(key: PopupThemeOriginKey.self, value: .bounds) { $0 }
                    .help(usesDarkAppearance ? (L.zh ? "切换日间模式" : "Use light appearance") : (L.zh ? "切换夜间模式" : "Use dark appearance"))

                    Divider().frame(height: 14).padding(.horizontal, 2)
                    Button {
                        AppQuitConfirmation.request()
                    } label: {
                        Image(systemName: "power")
                            .font(.system(size: 12))
                            .frame(width: 26, height: 26, alignment: .center)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .help(L.quit)
                }
            }
            .padding(.horizontal, PopupSpacing.section)
            .padding(.vertical, PopupSpacing.regular)

        }
        .frame(width: PopupLayout.width)
        .padding(.top, popupArrowX == nil ? 0 : PopupGlassOutline.arrowHeight)
        // One continuous backing avoids dark header/footer bands against the content.
        .background {
            PopupGlassOutline(arrowX: popupArrowX)
                .fill(PopupLayout.background.opacity(usesDarkAppearance ? 0.64 : 0.72))
        }
        .popupGlass(radius: 20, arrowX: popupArrowX)
        .accentColor(PopupLayout.accent)
        .environment(\.popupLiveUpdates, liveUpdates)
        .preferredColorScheme(preferredScheme)
        .onChange(of: popupAppearance) { _, appearance in onAppearanceChange(appearance) }
        .focusEffectDisabled()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            taskCenter.notificationService.refreshAuthorizationStatus()
        }
        .onReceive(tickTimer) { tickDate in
            // Relative labels only show minutes; do not invalidate the entire
            // glass panel once per second just to update an invisible clock.
            if tickDate.timeIntervalSince(now) >= 60 { now = tickDate }
            guard liveUpdates, menuVisible,
                  let active = store.accounts.first(where: { $0.isActive }),
                  !active.weeklyExhausted else { return }
            guard tickDate.timeIntervalSince(lastVisibleRefresh) >= refreshFrequency.selection.visibleInterval else { return }
            lastVisibleRefresh = tickDate
            Task {
                await refreshAccount(active)
                store.markActiveAccount()
            }
        }
        .onAppear {
            guard liveUpdates else { return }
            menuVisible = true
            taskCenter.notificationService.refreshAuthorizationStatus()
            lastVisibleRefresh = Date()
            // Auth already has a directory watcher; hooks are checked by their
            // app-level timer. Opening the UI should not reread either file.
            Task { await appUpdater.checkForUpdates(silent: true) }
        }
        .onDisappear {
            menuVisible = false
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().interpolation(.high)
                    .scaledToFit().frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                Text("CodexAppBar").font(.system(size: 17, weight: .medium))
            }
            Text(appUpdater.currentVersionDisplay).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            CodexResetWindowTipView()
            if isRefreshing {
                Text(L.refreshing).font(.system(size: 11)).foregroundStyle(.secondary)
            } else if let checked = store.accounts.compactMap({ $0.lastChecked }).max() {
                Circle().fill(CodexStatusPalette.ok).frame(width: 6, height: 6)
                Text(relativeTime(checked)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Button { Task { await refresh() } } label: {
                HeaderRefreshGlyph(isRefreshing: isRefreshing)
            }
            .popupGlassButton(iconOnly: true, busy: isRefreshing)
            .disabled(isRefreshing).help(refreshHelpText)
            .accessibilityLabel(L.refreshUsage)
            .accessibilityValue(isRefreshing ? L.refreshing : "")
        }
        .padding(.horizontal, 16).frame(height: 48)
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.zh ? "Codex 额度" : "Codex quota").font(.system(size: 13, weight: .medium))
                Spacer()
                AccountAvailabilitySummary(available: availableCount,
                                           unavailable: store.accounts.count - availableCount)
            }.frame(height: 25)
            if store.accounts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 28))
                    Text(L.noAccounts)
                    Text(L.addAccountHint).font(.caption)
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if let current = store.accounts.first(where: \.isActive) { accountRow(current) }
                if store.accounts.count <= 2 || (store.accounts.count == 3 && accountSectionHeight >= 290) {
                    VStack(spacing: 7) {
                        ForEach(backupAccounts) { account in accountRow(account) }
                    }
                } else {
                    AccountPoolScrollView(accountCount: backupAccounts.count) {
                        LazyVStack(spacing: 7) {
                            ForEach(backupAccounts) { account in accountRow(account) }
                        }
                    }.frame(maxHeight: .infinity)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
    }

    private func accountRow(_ account: TokenAccount) -> some View {
        AccountRowView(account: account, isActive: account.isActive, now: now,
                       isRefreshing: refreshingAccounts.contains(account.id), showsDetails: store.accounts.count <= 2, compactPool: store.accounts.count >= 3) {
            activateAccount(account)
        } onRefresh: { Task { await refreshAccount(account) } }
          onReauth: { reauthAccount(account) }
          onDelete: { store.remove(account) }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return L.justUpdated }
        if seconds < 3600 { return L.minutesAgo(seconds / 60) }
        return L.hoursAgo(seconds / 3600)
    }

    private func activateAccount(_ account: TokenAccount) {
        guard let key = store.key(for: account) else {
            showError = TokenStoreError.invalidAccount.localizedDescription
            return
        }
        let current = store.account(for: key) ?? account
        // team/SSO 账号导入时常无 id_token。直接激活会写空 id_token 到 auth.json，
        // Codex 报 "invalid ID token format"。先用 refresh_token 补一个 id_token 再激活。
        if current.idToken.isEmpty,
           RefreshService.shared.canRefreshWithoutUserInteraction(current) {
            Task {
                let result = await RefreshService.shared.refreshAndPersist(key: key, store: store)
                if result == .refreshed || result == .superseded,
                   let updated = store.account(for: key), !updated.idToken.isEmpty {
                    performActivate(key)
                } else {
                    showError = L.cannotActivateNoIdToken
                }
            }
            return
        }
        guard !current.idToken.isEmpty else {
            showError = L.cannotActivateNoIdToken
            return
        }
        performActivate(key)
    }

    private func performActivate(_ key: AccountKey) {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == "com.openai.codex"
        }

        // Codex 没跑：直接切，不打扰
        guard !running.isEmpty else {
            do { try store.activate(key) }
            catch { showError = error.localizedDescription }
            return
        }

        // Codex 在跑：给两种切换方式
        // - 仅切换：只写 auth.json，不退 Codex（不中断任务；Codex 下次重读 auth 才生效）
        // - 切换并重启：写 auth.json + 强退重开 Codex（立即生效，但中断进行中的任务）
        let alert = NSAlert()
        alert.messageText = L.switchModeTitle
        alert.informativeText = L.switchModeInfo
        alert.addButton(withTitle: L.switchOnly)         // .alertFirstButtonReturn
        alert.addButton(withTitle: L.switchAndRestart)   // .alertSecondButtonReturn
        alert.addButton(withTitle: L.cancel)             // .alertThirdButtonReturn
        let resp = PopupModalPresenter.run { alert.runModal() }
        guard resp != .alertThirdButtonReturn else { return }

        do {
            try store.activate(key)
        } catch {
            showError = error.localizedDescription
            return
        }
        if resp == .alertSecondButtonReturn {
            forceQuitCodexAndReopen(running)
        }
    }

    private func installCodexHooks() {
        let alert = NSAlert()
        alert.messageText = L.codexHookInstallConfirmTitle
        alert.informativeText = L.codexHookInstallConfirmInfo(codexHookInstaller.hooksURL.path)
        alert.addButton(withTitle: L.codexHookInstallConfirmButton)
        alert.addButton(withTitle: L.cancel)
        guard PopupModalPresenter.run({ alert.runModal() }) == .alertFirstButtonReturn else { return }

        do {
            try codexHookInstaller.install()
            showSuccess = L.codexHookInstallSuccess
            showError = nil
        } catch {
            showError = L.codexHookInstallFailed(error.localizedDescription)
            showSuccess = nil
        }
    }

    private func forceQuitCodexAndReopen(_ running: [NSRunningApplication]) {
        let ws = NSWorkspace.shared

        guard let url = ws.urlForApplication(withBundleIdentifier: "com.openai.codex") else {
            running.forEach { $0.forceTerminate() }
            return
        }
        var observer: NSObjectProtocol?
        observer = ws.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.openai.codex" else { return }
            ws.notificationCenter.removeObserver(observer!)
            ws.open(url)
        }

        running.forEach { $0.forceTerminate() }
    }

    private func refresh() async {
        let accountIDs = Set(store.accounts.map(\.id))
        isRefreshing = true
        refreshingAccounts.formUnion(accountIDs)

        async let radarRefresh: Void = CodexRadarService.shared.refresh()
        async let updateCheck: Void = appUpdater.checkForUpdates(silent: true)
        await RefreshService.shared.refreshExpiring(store: store)
        await WhamService.shared.refreshAll(store: store, forceSubscriptionRefresh: true)
        await radarRefresh
        await updateCheck
        lastVisibleRefresh = Date()
        TokenStatsService.shared.refresh()
        isRefreshing = false
        refreshingAccounts.subtract(accountIDs)
    }

    private func importAccounts() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L.importAccount
        guard PopupModalPresenter.run({ panel.runModal() }) == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        do {
            let accounts = try AccountImporter.parse(data)
            let importedKeys = try accounts.map { try store.upsertImportedAccount($0) }
            showSuccess = L.importedCount(accounts.count)
            Task {
                for key in importedKeys {
                    await WhamService.shared.refreshOne(key: key, store: store)
                }
            }
        } catch {
            showError = error.localizedDescription
        }
    }

    private func refreshAccount(_ account: TokenAccount) async {
        let accountID = account.id
        refreshingAccounts.insert(accountID)
        defer { refreshingAccounts.remove(accountID) }

        guard let key = store.key(for: account) else { return }
        RefreshService.shared.syncActiveFromAuthJson(store: store)
        if let current = store.account(for: key), RefreshService.shared.needsRefresh(current) {
            _ = await RefreshService.shared.refreshAndPersist(key: key, store: store)
        }
        await WhamService.shared.refreshOne(key: key, store: store)
    }

    private func reauthAccount(_ account: TokenAccount) {
        guard let key = store.key(for: account) else {
            showError = TokenStoreError.invalidAccount.localizedDescription
            return
        }
        let current = store.account(for: key) ?? account
        // Codex owns the active account's rolling refresh token. Never rotate it here or the
        // two processes can consume the same generation and revoke the newly authorized session.
        // Only inactive accounts are eligible for silent recovery.
        if RefreshService.shared.canRefreshWithoutUserInteraction(current) {
            Task {
                switch await RefreshService.shared.refreshAndPersist(key: key, store: store) {
                case .refreshed, .superseded:
                    await WhamService.shared.refreshOne(key: key, store: store)
                case .needsReauthorization:
                    startReauthOAuth(replacing: key)
                case .transientFailure:
                    showError = L.tokenRefreshFailed
                case .missing:
                    break
                }
            }
            return
        }
        startReauthOAuth(replacing: key)
    }

    private func startReauthOAuth(replacing key: AccountKey) {
        showError = nil
        oauth.startOAuth { result in
            switch result {
            case .success(let tokens):
                let authorized = AccountBuilder.build(from: tokens)
                do {
                    let committedKey = try store.commitOAuthAccount(authorized, replacing: key)
                    Task { await WhamService.shared.refreshOne(key: committedKey, store: store) }
                } catch {
                    showError = error.localizedDescription
                }
            case .failure(let error):
                if case OAuthError.cancelled = error { break }
                showError = error.localizedDescription
            }
        }
    }
}

private struct AppUpdateRow: View {
    @EnvironmentObject private var language: LanguageSettings
    @ObservedObject var updater: AppUpdateService

    var body: some View {
        let _ = language.identity
        AppUpdateStatusCard(
            content: .state(updater.state, progress: updater.downloadProgress),
            onPrimary: {
                Task { @MainActor in
                    if case .readyToInstall = updater.state {
                        await updater.installDownloadedUpdate()
                    } else {
                        await updater.downloadLatest()
                    }
                }
            }
        )
    }
}

private struct AppUpdateCompletedRow: View {
    @EnvironmentObject private var language: LanguageSettings
    let completion: AppUpdateCompletion
    let dismiss: () -> Void

    var body: some View {
        let _ = language.identity
        AppUpdateStatusCard(content: .completed(completion), onDismiss: dismiss)
    }
}

private struct StatusLightsToggleIcon: View {
    let isOn: Bool

    var body: some View {
        HStack(spacing: 2.2) {
            light(.red, active: isOn)
            light(.yellow, active: isOn)
            light(.green, active: isOn)
        }
        .opacity(isOn ? 1 : 0.45)
    }

    private func light(_ color: Color, active: Bool) -> some View {
        Circle()
            .fill(active ? color : Color.secondary.opacity(0.45))
            .frame(width: 5.2, height: 5.2)
    }
}

struct CodexHookSetupRow: View {
    let state: CodexHookInstallState
    let installAction: () -> Void

    private var title: String {
        switch state {
        case .needsUpdate:
            return L.codexHookUpdateTitle
        case .error:
            return L.codexHookErrorTitle
        case .checking, .missing, .installed:
            return L.codexHookSetupTitle
        }
    }

    private var buttonTitle: String {
        state == .needsUpdate ? L.codexHookUpdateButton : L.codexHookInstallButton
    }

    var body: some View {
        HStack(alignment: .top, spacing: PopupSpacing.regular) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.orange)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: PopupSpacing.compact) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                Text(L.codexHookSetupDetail)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: PopupSpacing.regular)

            Button(action: installAction) {
                Text(buttonTitle)
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .foregroundColor(.accentColor)
        }
        .padding(.horizontal, PopupSpacing.section)
        .padding(.vertical, PopupSpacing.regular)
    }
}
