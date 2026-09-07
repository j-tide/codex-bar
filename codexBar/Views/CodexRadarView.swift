import AppKit
import SwiftUI

struct CodexRadarView: View {
    @EnvironmentObject var language: LanguageSettings
    @ObservedObject private var radar = CodexRadarService.shared

    var body: some View {
        let _ = language.identity
        CodexRadarQualityContent(
            report: radar.intelligence,
            isRefreshing: radar.isRefreshing,
            error: radar.lastError,
            refresh: { Task { await radar.refresh() } },
            openSource: { NSWorkspace.shared.open(radar.homepageURL) }
        )
        .task {
            if radar.needsVisibleRefresh { await radar.refresh() }
        }
    }
}

struct CodexRadarQualityContent: View {
    let report: CodexRadarIntelligenceReport?
    let isRefreshing: Bool
    let error: String?
    var refresh: () -> Void = {}
    var openSource: () -> Void = {}
    @State private var showsScoreExplanation = false

    private var matrix: CodexRadarMatrix {
        CodexRadarPresentation.matrix(from: report?.modelIQ(for: .comprehensive))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if matrix.rows.isEmpty {
                emptyState
            } else {
                CodexRadarLeaderboardView(matrix: matrix)
                footer
            }
        }
        .frame(width: 300 - PopupSpacing.section * 2, alignment: .leading)
        .padding(.horizontal, PopupSpacing.section)
        .padding(.vertical, PopupSpacing.regular)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RadarQualityStyle.accent)
                .accessibilityHidden(true)
            Text(L.radarScoreTitle)
                .font(.system(size: 12, weight: .semibold))
            Button {
                showsScoreExplanation.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .foregroundStyle(.secondary)
            .help(L.radarScoreExplanationTitle)
            .accessibilityLabel(L.radarScoreExplanationTitle)
            .popover(isPresented: $showsScoreExplanation, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L.radarScoreExplanationTitle)
                        .font(.system(size: 12, weight: .semibold))
                    Text(L.radarScoreMethod)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 240, alignment: .leading)
                .padding(14)
            }
            Spacer(minLength: 0)
            Button(action: refresh) {
                RefreshIconView(isRefreshing: isRefreshing, size: 14, fontSize: 10, weight: .medium)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .focusEffectDisabled()
            .foregroundStyle(.secondary)
            .disabled(isRefreshing)
            .help(L.modelQualityRefreshHelp)
            .accessibilityLabel(L.modelQualityRefreshHelp)
            Button(action: openSource) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .focusEffectDisabled()
            .foregroundStyle(.secondary)
            .help(L.modelQualityOpenHelp)
            .accessibilityLabel(L.modelQualityOpenHelp)
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if error != nil {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(CodexStatusPalette.warning)
                Text(L.radarScoreCached)
                    .foregroundStyle(.secondary)
                    .help(error ?? "")
            } else {
                Text("Codex Radar")
                    .foregroundStyle(.secondary)
            }
            if let date = report?.updatedAt(for: .comprehensive) {
                Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .help(L.radarScoreUpdated)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 9))
        .lineLimit(1)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: isRefreshing ? "ellipsis" : "wifi.exclamationmark")
                    .foregroundStyle(RadarQualityStyle.accent)
                Text(isRefreshing ? L.modelQualityReading : L.modelQualityNoData)
                    .font(.system(size: 11, weight: .medium))
            }
            Text(error ?? L.radarScoreMethod)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
    }
}

struct CodexRadarLeaderboardView: View {
    let matrix: CodexRadarMatrix
    @State private var hoveredID: String?

    private var rankedCells: [CodexRadarMatrixCell] {
        matrix.rankedCellIDs.compactMap { matrix.cell(id: $0) }
    }

    var body: some View {
        rows(Array(rankedCells.prefix(6)))
    }

    private func rows(_ cells: [CodexRadarMatrixCell]) -> some View {
        VStack(spacing: 0) {
            ForEach(cells) { cell in
                row(cell, rank: matrix.rank(of: cell) ?? 1)
            }
        }
    }

    private func row(_ cell: CodexRadarMatrixCell, rank: Int) -> some View {
        HStack(spacing: 9) {
            Text(String(format: "%02d", rank))
                .font(.system(size: 10, weight: rank == 1 ? .bold : .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(rankColor(rank))
                .frame(width: 19)

            Text(cell.rowName)
                .font(.system(size: 11, weight: rank == 1 ? .semibold : .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            Text(cell.effort)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(RadarQualityStyle.effortColor(cell.effort))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(RadarQualityStyle.effortColor(cell.effort).opacity(0.10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(RadarQualityStyle.effortColor(cell.effort).opacity(0.18), lineWidth: 0.5)
                        }
                }

            Spacer(minLength: 2)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("IQ")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f", cell.score))
                    .font(.system(size: rank == 1 ? 21 : 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(rank == 1 ? RadarQualityStyle.accent : Color.primary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: rank == 1 ? 38 : 29)
        .background {
            if rank == 1 {
                RoundedRectangle(cornerRadius: 7)
                    .fill(RadarQualityStyle.accent.opacity(0.085))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(RadarQualityStyle.accent.opacity(0.16), lineWidth: 0.5)
                    }
            } else if hoveredID == cell.id {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(0.035))
            }
        }
        .contentShape(Rectangle())
        .onHover { hoveredID = $0 ? cell.id : (hoveredID == cell.id ? nil : hoveredID) }
        .help("\(cell.displayName) · IQ \(String(format: "%.2f", cell.score))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.modelQualityCellAccessibility(
            model: cell.displayName,
            score: CodexRadarPresentation.scoreText(cell.score),
            passCount: nil,
            rank: rank
        ))
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 0.70, green: 0.49, blue: 0.13)
        case 2: return .secondary
        case 3: return Color(red: 0.65, green: 0.42, blue: 0.29)
        default: return .secondary.opacity(0.75)
        }
    }
}

private enum RadarQualityStyle {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.32, green: 0.80, blue: 0.84, alpha: 1)
            : NSColor(calibratedRed: 0.08, green: 0.45, blue: 0.49, alpha: 1)
    })

    static func effortColor(_ effort: String) -> Color {
        switch effort {
        case "low": return low
        case "medium": return medium
        case "high": return high
        case "xhigh": return xhigh
        case "max": return max
        case "ultra": return ultra
        default: return .secondary
        }
    }

    private static let low = adaptive(light: (0.13, 0.43, 0.30), dark: (0.43, 0.79, 0.59))
    private static let medium = adaptive(light: (0.17, 0.39, 0.69), dark: (0.48, 0.70, 0.97))
    private static let high = adaptive(light: (0.53, 0.37, 0.08), dark: (0.89, 0.74, 0.35))
    private static let xhigh = adaptive(light: (0.68, 0.31, 0.13), dark: (0.98, 0.61, 0.36))
    private static let max = adaptive(light: (0.46, 0.30, 0.72), dark: (0.73, 0.60, 0.98))
    private static let ultra = adaptive(light: (0.66, 0.24, 0.46), dark: (0.95, 0.53, 0.74))

    private static func adaptive(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(calibratedRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }

}

struct CodexResetWindowTipView: View {
    @EnvironmentObject var language: LanguageSettings
    @ObservedObject private var radar = CodexRadarService.shared
    private let infoAccent = Color(red: 0.12, green: 0.33, blue: 0.82)

    var body: some View {
        let _ = language.identity

        if let resetWindow {
            HStack(spacing: PopupSpacing.regular) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(infoAccent)
                    .frame(width: 17, height: 17)
                    .background(
                        Circle()
                            .fill(infoAccent.opacity(0.12))
                    )

                tipText(for: resetWindow)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .monospacedDigit()

                Spacer(minLength: PopupSpacing.regular)

                Button {
                    NSWorkspace.shared.open(resetWindow.sourceURL ?? radar.homepageURL)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .foregroundColor(infoAccent)
                .help(L.codexResetWindowSourceHelp)
                .accessibilityLabel(L.codexResetWindowSourceHelp)
            }
            .frame(height: 31)
            .padding(.horizontal, PopupSpacing.regular)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(infoAccent.opacity(0.075))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(infoAccent.opacity(0.14), lineWidth: 0.8)
                    )
            )
            .padding(.horizontal, PopupSpacing.section)
            .padding(.bottom, PopupSpacing.regular)
            .help(resetWindow.message ?? L.codexResetWindowFallback)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var resetWindow: CodexRadarResetWindow? {
        guard let snapshot = radar.snapshot,
              let window = snapshot.window,
              window.isOpen || snapshot.windowOpen == true || snapshot.status?.lowercased() == "open" else {
            return nil
        }
        return window
    }

    private func tipText(for window: CodexRadarResetWindow) -> Text {
        guard let expectedResetAt = window.expectedResetAt else {
            return Text(L.codexResetWindowFallback)
                .foregroundColor(.primary)
        }
        return Text(L.codexResetWindowOpen(formattedResetDate(expectedResetAt)))
            .foregroundColor(.primary)
    }

    private func formattedResetDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L.zh ? "zh_CN" : "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = L.zh ? "M/d HH:mm" : "MMM d HH:mm"
        return formatter.string(from: date)
    }
}
