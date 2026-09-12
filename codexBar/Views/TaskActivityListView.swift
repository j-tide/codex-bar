import SwiftUI
import AppKit
import UserNotifications

/// Both rows use the same column metric; borders cannot drift with their contents.
enum PopupLayout {
    static let width: CGFloat = 736
    static let columnWidth: CGFloat = (width - 1) / 2
    static let insightsHeight: CGFloat = 210
    static var activityHeight: CGFloat {
        min(372, max(220, (NSScreen.main?.visibleFrame.height ?? 800) - 310))
    }
    static let background = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.145, green: 0.153, blue: 0.173, alpha: 1)
            : NSColor(red: 0.973, green: 0.977, blue: 0.985, alpha: 1)
    })
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.510, green: 0.718, blue: 1, alpha: 1) : .systemBlue
    })
    static let plan = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.780, green: 0.659, blue: 0.961, alpha: 1) : .systemPurple
    })
    static let sidebar = Color.primary.opacity(0.025)
}

private struct PopupLiveUpdatesKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var popupLiveUpdates: Bool {
        get { self[PopupLiveUpdatesKey.self] }
        set { self[PopupLiveUpdatesKey.self] = newValue }
    }
}

struct TaskActivityListView: View {
    @Environment(\.popupLiveUpdates) private var liveUpdates
    @EnvironmentObject var taskCenter: TaskCenterService
    @EnvironmentObject var language: LanguageSettings
    @EnvironmentObject var codexHookInstaller: CodexHookInstallerService
    let onOpenNotificationSettings: (@escaping (Bool) -> Void) -> Void
    let onInstallHooks: () -> Void

    var body: some View {
        let records = taskCenter.displayRecords
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Text(L.zh ? "对话活动" : "Task activity").font(.system(size: 13, weight: .medium)).fixedSize()
                ActivitySummaryStrip(attention: taskCenter.snapshot.needsAttentionCount,
                                     running: taskCenter.snapshot.runningCount,
                                     unread: taskCenter.snapshot.readyCount)
                Spacer()
                TaskNotificationControl(openSettings: onOpenNotificationSettings, notifications: taskCenter.notificationService)
            }.frame(height: 25)

            if codexHookInstaller.state.needsAction {
                CodexHookSetupRow(state: codexHookInstaller.state, installAction: onInstallHooks)
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(records) { record in
                        TaskActivityRow(record: record, metadata: taskCenter.metadata[record.taskKey])
                    }
                    if records.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 25))
                            Text(L.zh ? "暂无对话活动" : "No task activity")
                            Text(L.zh ? "Codex 的任务状态会显示在这里" : "Codex task activity appears here")
                                .font(.system(size: 11))
                        }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 50)
                    }
                }
            }
            if taskCenter.snapshot.unreadableCount > 0 {
                Text(L.zh ? "部分状态暂时无法读取" : "Some task states could not be read")
                    .font(.system(size: 10)).foregroundStyle(CodexStatusPalette.warning)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .task {
            guard liveUpdates else { return }
            repeat {
                taskCenter.refreshMetadata()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            } while !Task.isCancelled
        }
    }
}

private struct ActivitySummaryStrip: View {
    @EnvironmentObject private var language: LanguageSettings
    let attention: Int
    let running: Int
    let unread: Int

    private struct Item: Identifiable {
        let id: Int
        let count: Int
        let title: String
        let symbol: String
        let color: Color
    }

    private var items: [Item] {
        [Item(id: 0, count: attention, title: L.zh ? "需处理" : "Need you", symbol: "exclamationmark.bubble.fill", color: CodexStatusPalette.danger),
         Item(id: 1, count: running, title: L.zh ? "进行中" : "Running", symbol: "arrow.trianglehead.2.clockwise.rotate.90", color: CodexStatusPalette.running),
         Item(id: 2, count: unread, title: L.zh ? "待查看" : "Unread", symbol: "checkmark.circle.fill", color: CodexStatusPalette.ok)]
            .filter { $0.count > 0 }
    }

    var body: some View {
        let _ = language.identity
        if !items.isEmpty {
            ViewThatFits(in: .horizontal) {
                strip(showTitles: true)
                strip(showTitles: false)
            }
            .popupGlass(radius: PopupControlMetrics.compactRadius)
        }
    }

    private func strip(showTitles: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                if item.id != items.first?.id {
                    Rectangle().fill(.primary.opacity(0.09)).frame(width: 0.5, height: 10)
                }
                ActivitySummaryBadge(count: item.count, title: item.title, symbol: item.symbol,
                                     color: item.color, showTitle: showTitles)
            }
        }.fixedSize()
    }
}

private struct ActivitySummaryBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let count: Int
    let title: String
    let symbol: String
    let color: Color
    let showTitle: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .medium))
            Text("\(count)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .contentTransition(.numericText())
            if showTitle { Text(title).font(.system(size: 9, weight: .medium)).lineLimit(1) }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .frame(height: 22)
        .help("\(title) · \(count)")
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(String(count))
    }
}

private struct TaskNotificationControl: View {
    @AppStorage("languageOverride") private var chinese = L.systemIsChinese
    let openSettings: (@escaping (Bool) -> Void) -> Void
    @ObservedObject var notifications: TaskNotificationService
    @Environment(\.popupLiveUpdates) private var liveUpdates
    @State private var showsPermissionHelp = false
    @State private var settingsOpenFailed = false

    private var systemBlocked: Bool { notifications.authorizationStatus == .denied }
    private var actionLabel: String {
        if systemBlocked { return L.zh ? "系统通知已关闭 · 查看开启方式" : "System notifications are off · How to enable" }
        return notifications.isEnabled
            ? (L.zh ? "关闭任务提醒" : "Turn off task notifications")
            : (L.zh ? "开启任务提醒" : "Turn on task notifications")
    }

    var body: some View {
        let _ = chinese
        Button {
            Task {
                NSApplication.shared.activate(ignoringOtherApps: true)
                await notifications.toggleFromUserAction()
                showsPermissionHelp = notifications.authorizationIssue != nil
                settingsOpenFailed = false
            }
        } label: {
            if notifications.isUpdatingAuthorization { ProgressView().controlSize(.mini) }
            else {
                Image(systemName: notifications.isEnabled ? "bell" : "bell.slash")
                    .font(.system(size: 13))
            }
        }
        .popupGlassButton(iconOnly: true).disabled(notifications.isUpdatingAuthorization)
        .help(actionLabel).accessibilityLabel(actionLabel)
        .accessibilityValue(notifications.isEnabled ? (L.zh ? "已开启" : "On") : (L.zh ? "已关闭" : "Off"))
        .popover(isPresented: $showsPermissionHelp, arrowEdge: .bottom) { permissionHelp }
        .onChange(of: notifications.isEnabled) { _, enabled in
            if enabled { showsPermissionHelp = false }
        }
        .task {
            guard liveUpdates else { return }
            repeat {
                await notifications.refreshAuthorizationStatusNow()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            } while !Task.isCancelled
        }
    }

    private var permissionHelp: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(systemBlocked ? (L.zh ? "通知被系统关闭" : "Notifications are off in macOS")
                  : (L.zh ? "暂时无法开启提醒" : "Could not enable notifications"), systemImage: "bell.slash")
                .font(.system(size: 12, weight: .semibold))
            Text(systemBlocked
                 ? (L.zh ? "在系统设置的通知列表中找到 CodexAppBar，打开“允许通知”。返回后会自动同步。"
                    : "Find CodexAppBar in System Settings → Notifications and turn on Allow Notifications. This app will update when you return.")
                 : (L.zh ? "系统尚未完成授权，请重试。" : "System authorization did not complete. Please retry."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if case .requestFailed(let detail) = notifications.authorizationIssue {
                DisclosureGroup(L.zh ? "错误详情" : "Error details") {
                    Text(detail).font(.system(size: 10)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }.font(.system(size: 10))
            }
            if settingsOpenFailed {
                Text(L.zh ? "无法自动打开，请手动前往系统设置 → 通知。" : "Open System Settings → Notifications manually.")
                    .font(.system(size: 10)).foregroundStyle(CodexStatusPalette.warning)
            }
            HStack {
                Button(L.zh ? "稍后" : "Later") { showsPermissionHelp = false }
                    .buttonStyle(.borderless).focusable(false)
                Spacer()
                Button(systemBlocked ? (L.zh ? "打开通知设置" : "Notification Settings") : (L.zh ? "重新申请" : "Try Again")) {
                    if systemBlocked {
                        showsPermissionHelp = false
                        openSettings { success in
                            settingsOpenFailed = !success
                            if !success { showsPermissionHelp = true }
                        }
                    } else {
                        Task {
                            NSApplication.shared.activate(ignoringOtherApps: true)
                            if await notifications.enable() { showsPermissionHelp = false }
                        }
                    }
                }
                .popupGlassButton(tint: PopupLayout.accent)
                .font(.system(size: 11, weight: .medium))
                .disabled(notifications.isUpdatingAuthorization)
            }
        }.padding(14).frame(width: 260)
    }
}

private struct TaskActivityRow: View {
    @AppStorage("languageOverride") private var chinese = L.systemIsChinese
    @EnvironmentObject private var taskCenter: TaskCenterService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let record: TaskActivityRecord
    let metadata: CodexTaskMetadata?
    @State private var hovered = false
    private var running: Bool { record.state == .running && !record.isStale }
    private var attention: Bool { record.state == .needsAttention }
    private var stateColor: Color {
        record.isStale ? .secondary : attention ? CodexStatusPalette.danger
            : running ? CodexStatusPalette.running : record.state == .ready ? CodexStatusPalette.ok : .secondary
    }
    private var title: String {
        metadata?.title ?? "\(L.zh ? "对话" : "Conversation") · \(record.taskKey.prefix(6))"
    }
    private var projectName: String? { metadata?.projectName }
    private var primaryTitle: String { projectName ?? title }
    private var subtitle: String {
        projectName != nil ? title : (L.zh ? "未关联项目" : "No project")
    }
    private var stateText: String {
        if record.isStale { return L.zh ? "状态已过期" : "Stale status" }
        if record.state == .ready { return L.zh ? "完成 · 未读" : "Done · unread" }
        return L.taskStatusPhase(record.phase)
    }
    var body: some View {
        let _ = chinese
        Button {
            if CodexApplicationActivator.openTask(metadata?.threadID) { taskCenter.markRead(record) }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: projectName == nil ? "bubble.left.fill" : "folder.fill")
                            .font(.system(size: 11)).foregroundStyle(PopupLayout.accent)
                            .accessibilityHidden(true)
                        Text(primaryTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary).lineLimit(1).truncationMode(projectName == nil ? .tail : .middle)
                    }
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    if running { TaskRunningIndicator().frame(width: 11, height: 11) }
                    else { Image(systemName: attention ? "exclamationmark" : record.isStale ? "clock" : "checkmark") }
                    Text(stateText).lineLimit(1)
                }.font(.system(size: 11)).foregroundStyle(stateColor)
                Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).frame(height: 44)
            .background(attention ? CodexStatusPalette.danger.opacity(0.09) : Color.primary.opacity(hovered ? 0.045 : 0), in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .leading) {
                if attention { RoundedRectangle(cornerRadius: 2).fill(CodexStatusPalette.danger).frame(width: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).focusable(false).focusEffectDisabled().onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: record.state)
        .help("\(primaryTitle) · \(subtitle)\n\(stateText) · \(L.zh ? "打开 Codex" : "Open Codex")")
        .accessibilityLabel("\(primaryTitle), \(subtitle), \(stateText)")
    }
}

struct TaskRunningIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.popupLiveUpdates) private var liveUpdates
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !liveUpdates)) { context in
            let phase = reduceMotion || !liveUpdates ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            ZStack {
                Circle().stroke(CodexStatusPalette.running.opacity(0.20), lineWidth: 1.5)
                // Keep both rounded caps away from the angular gradient's 0/1
                // seam. A cap at zero samples the bright end and creates a stray dot.
                Circle().trim(from: 0.10, to: 0.88)
                    .stroke(AngularGradient(stops: [
                        .init(color: CodexStatusPalette.running.opacity(0.32), location: 0),
                        .init(color: CodexStatusPalette.running.opacity(0.32), location: 0.10),
                        .init(color: CodexStatusPalette.running.opacity(0.65), location: 0.49),
                        .init(color: CodexStatusPalette.running, location: 0.88),
                        .init(color: CodexStatusPalette.running, location: 1)
                    ], center: .center), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                    .rotationEffect(.degrees(phase * 360))
            }.padding(0.85)
        }.accessibilityHidden(true)
    }
}
