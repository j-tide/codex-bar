import AppKit
import SwiftUI

enum AppUpdateCardTone {
    case neutral
    case accent
    case success
    case failure

    var color: Color {
        switch self {
        case .neutral: return .secondary
        case .accent: return PopupLayout.accent
        case .success: return CodexStatusPalette.ok
        case .failure: return CodexStatusPalette.danger
        }
    }
}

enum AppUpdateCardAction: Equatable {
    case none
    case download
    case install
    case retry

    var title: String? {
        switch self {
        case .none: return nil
        case .download: return L.downloadUpdate
        case .install: return L.installUpdateNow
        case .retry: return L.retry
        }
    }
}

struct AppUpdateCardContent {
    let title: String
    let detail: String
    let symbol: String
    let tone: AppUpdateCardTone
    let action: AppUpdateCardAction
    let progress: Double?
    let dismissible: Bool
    let isBusy: Bool
    let confirmationTitle: String?

    static func state(_ state: AppUpdateState, progress: Double) -> Self {
        switch state {
        case .idle:
            return .init(title: L.checkForUpdates, detail: "", symbol: "arrow.triangle.2.circlepath",
                         tone: .neutral, action: .none, progress: nil, dismissible: false, isBusy: false,
                         confirmationTitle: nil)
        case .checking:
            return .init(title: L.updateChecking, detail: L.updateCheckingDetail,
                         symbol: "arrow.triangle.2.circlepath", tone: .neutral,
                         action: .none, progress: nil, dismissible: false, isBusy: true,
                         confirmationTitle: nil)
        case .available(let release):
            return .init(title: L.updateAvailableTitle(release.tagName),
                         detail: L.updateAvailableDetail(formattedSize(release.assetSize)),
                         symbol: "arrow.down.circle", tone: .accent,
                         action: .download, progress: nil, dismissible: false, isBusy: false,
                         confirmationTitle: nil)
        case .downloading(let release):
            return .init(title: L.updateDownloading,
                         detail: L.updateDownloadingDetail(Int(progress * 100), formattedSize(release.assetSize)),
                         symbol: "arrow.down.circle", tone: .accent,
                         action: .none, progress: progress, dismissible: false, isBusy: false,
                         confirmationTitle: nil)
        case .readyToInstall(let release):
            return .init(title: L.updateReadyToInstall,
                         detail: L.updateReadyToInstallDetail(release.displayName),
                         symbol: "checkmark.circle", tone: .success,
                         action: .install, progress: nil, dismissible: false, isBusy: false,
                         confirmationTitle: L.updateInstallConfirmTitle(release.tagName))
        case .installing:
            return .init(title: L.updateInstalling, detail: L.updateInstallingDetail,
                         symbol: "shippingbox", tone: .accent,
                         action: .none, progress: nil, dismissible: false, isBusy: true,
                         confirmationTitle: nil)
        case .upToDate:
            return .init(title: L.updateUpToDate, detail: L.updateUpToDateDetail,
                         symbol: "checkmark.circle", tone: .success,
                         action: .none, progress: nil, dismissible: false, isBusy: false,
                         confirmationTitle: nil)
        case .failed(let message):
            return .init(title: L.updateFailedTitle, detail: message,
                         symbol: "exclamationmark.triangle", tone: .failure,
                         action: .retry, progress: nil, dismissible: false, isBusy: false,
                         confirmationTitle: nil)
        }
    }

    static func completed(_ completion: AppUpdateCompletion) -> Self {
        .init(title: L.updateInstalledTitle(completion.tagName),
              detail: L.updateInstalledDetail(completion.currentVersion),
              symbol: "checkmark.circle", tone: .success,
              action: .none, progress: nil, dismissible: true, isBusy: false,
              confirmationTitle: nil)
    }

    private static func formattedSize(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct AppUpdateStatusCard: View {
    let content: AppUpdateCardContent
    var onPrimary: () -> Void
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsInstallConfirmation = false

    init(
        content: AppUpdateCardContent,
        onPrimary: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {},
        initiallyConfirming: Bool = false
    ) {
        self.content = content
        self.onPrimary = onPrimary
        self.onDismiss = onDismiss
        _showsInstallConfirmation = State(initialValue: initiallyConfirming)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                Group {
                    if content.isBusy {
                        UpdateOrbitIndicator()
                    } else {
                        Image(systemName: content.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(content.tone.color)
                    }
                }
                .frame(width: 30, height: 30)
                .background((content.isBusy ? PopupLayout.accent : content.tone.color).opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(showsInstallConfirmation ? (content.confirmationTitle ?? content.title) : content.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    let detail = showsInstallConfirmation ? L.updateInstallConfirmInfo : content.detail
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(content.tone == .failure ? 3 : 2)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(detail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showsInstallConfirmation && content.action == .install {
                    Button { showsInstallConfirmation = false } label: {
                        Text(L.later)
                            .font(.system(size: 12, weight: .medium))
                            .frame(height: 24)
                    }
                    .popupGlassButton()
                    Button(action: onPrimary) {
                        Text(L.updateInstallConfirmButton)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(height: 24)
                    }
                    .popupGlassButton(tint: CodexStatusPalette.ok)
                }

                if let title = content.action.title, !showsInstallConfirmation {
                    Button {
                        if content.action == .install {
                            showsInstallConfirmation = true
                        } else {
                            onPrimary()
                        }
                    } label: {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(height: 24)
                    }
                    .popupGlassButton(tint: content.tone.color)
                    .accessibilityLabel(title)
                }

                if content.dismissible {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 20, height: 24)
                    }
                    .popupGlassButton()
                    .help(L.dismissUpdateInstalled)
                    .accessibilityLabel(L.dismissUpdateInstalled)
                }
            }

            if let progress = content.progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.09))
                        Capsule().fill(content.tone.color)
                            .frame(width: geometry.size.width * min(max(progress, 0), 1))
                    }
                }
                .frame(height: 4)
                .padding(.leading, 40)
                .accessibilityLabel(L.updateDownloading)
                .accessibilityValue("\(Int(progress * 100))%")
            }

        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: showsInstallConfirmation)
        .onChange(of: content.action) { _, action in
            if action != .install { showsInstallConfirmation = false }
        }
    }
}

private struct UpdateOrbitIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(PopupLayout.accent.opacity(0.18), lineWidth: 1)
                .frame(width: 20, height: 20)

            Circle()
                .trim(from: 0.04, to: 0.39)
                .stroke(
                    AngularGradient(colors: [PopupLayout.accent.opacity(0.25), PopupLayout.accent,
                                             CodexStatusPalette.ok], center: .center),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                )
                .frame(width: 20, height: 20)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(reduceMotion ? nil : .linear(duration: 1.5).repeatForever(autoreverses: false),
                           value: isAnimating)

            Circle()
                .trim(from: 0.02, to: 0.31)
                .stroke(CodexStatusPalette.ok.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(isAnimating ? -360 : 0))
                .animation(reduceMotion ? nil : .linear(duration: 2.2).repeatForever(autoreverses: false),
                           value: isAnimating)

            Circle()
                .fill(PopupLayout.accent)
                .frame(width: 3, height: 3)
                .shadow(color: PopupLayout.accent.opacity(0.7), radius: 3)
        }
        .frame(width: 24, height: 24)
        .onAppear { isAnimating = !reduceMotion }
        .onChange(of: reduceMotion) { _, reduced in isAnimating = !reduced }
    }
}

#if DEBUG
@MainActor
enum AppUpdateGalleryWindow {
    private static var window: NSWindow?

    static func show() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--update-gallery-zh") {
            UserDefaults.standard.setVolatileDomain(["languageOverride": true], forName: UserDefaults.argumentDomain)
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: PopupLayout.width, height: 650),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CodexAppBar · Update components"
        if arguments.contains("--update-gallery-dark") {
            window.appearance = NSAppearance(named: .darkAqua)
        }
        window.contentView = NSHostingView(rootView: AppUpdateStatusGallery())
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

struct AppUpdateStatusGallery: View {
    private let release = AppUpdateRelease(
        tagName: "v2026.09.14.4", title: "CodexAppBar v2026.09.14.4",
        assetName: "codexAppBar-release.zip", assetURL: URL(string: "https://example.com/update.zip")!,
        assetSize: 3_120_000, assetDigest: nil
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("CodexAppBar · Update states")
                    .font(.system(size: 20, weight: .semibold))
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    AppUpdateStatusCard(content: card, initiallyConfirming: index == 4)
                }
            }
            .padding(20)
        }
        .frame(width: PopupLayout.width)
        .background(PopupLayout.background)
    }

    private var cards: [AppUpdateCardContent] {
        [
            .state(.checking, progress: 0),
            .state(.available(release), progress: 0),
            .state(.downloading(release), progress: 0.42),
            .state(.readyToInstall(release), progress: 1),
            .state(.readyToInstall(release), progress: 1),
            .state(.installing(release), progress: 1),
            .state(.upToDate, progress: 0),
            .state(.failed("下载包 SHA-256 校验不一致，请重新下载。"), progress: 0),
            .completed(.init(tagName: release.tagName, currentVersion: release.tagName))
        ]
    }
}

#Preview("Update components") {
    AppUpdateStatusGallery()
}
#endif
