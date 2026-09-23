import AppKit
import SwiftUI

struct CodexRadarView: View {
    @Environment(\.popupLiveUpdates) private var liveUpdates
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
            if liveUpdates, radar.needsVisibleRefresh { await radar.refresh() }
        }
    }
}

struct CodexRadarQualityContent: View {
    @AppStorage("languageOverride") private var chinese = L.systemIsChinese
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
        let _ = chinese
        VStack(alignment: .leading, spacing: 10) {
            header

            if matrix.rows.isEmpty {
                emptyState
            } else {
                CodexRadarTableView(matrix: matrix).zIndex(1)
                footer
                Text(L.zh ? "显示取整 · 悬停查看原始分数与排名依据" : "Rounded values · hover for precise scores and ranking")
                    .font(.system(size: 8)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RadarQualityStyle.accent)
                .accessibilityHidden(true)
            Text(L.radarScoreTitle)
                .font(.system(size: 13, weight: .medium))
            Text("IQ").font(.system(size: 10)).foregroundStyle(.secondary)
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
                    .contentShape(Rectangle())
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
                    .contentShape(Rectangle())
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

/// All model rows remain visible; columns share the available width without scrolling.
struct CodexRadarTableView: View {
    @AppStorage("languageOverride") private var chinese = L.systemIsChinese
    @Environment(\.colorScheme) private var colorScheme
    let matrix: CodexRadarMatrix
    @State private var hoveredID: String?
    private let modelWidth: CGFloat = 82
    private let rowHeight: CGFloat = 28
    static func height(rowCount: Int) -> CGFloat { 20 + CGFloat(rowCount) * 30 }

    var body: some View {
        let _ = chinese
        GeometryReader { geometry in
            let cellWidth = max(0, (geometry.size.width - modelWidth) / CGFloat(max(matrix.columns.count, 1)))
            VStack(spacing: 2) {
                HStack(spacing: 0) {
                    Text(L.zh ? "模型" : "Model")
                        .frame(width: modelWidth, alignment: .leading)
                    ForEach(matrix.columns) { column in
                        Text(column.label).lineLimit(1).minimumScaleFactor(0.72)
                            .frame(width: cellWidth).help(column.id)
                    }
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(height: 18)
                ForEach(matrix.rows) { row in
                    HStack(spacing: 0) {
                        HStack(spacing: 4) {
                            Image(systemName: row.family.symbolName)
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(row.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.72)
                        }
                        .frame(width: modelWidth, alignment: .leading)
                        .help(row.displayName)
                        ForEach(matrix.columns) { column in
                            score(row.cell(for: column.id), row: row, effort: column.id)
                                .frame(width: cellWidth, height: rowHeight)
                        }
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if let cell = matrix.cell(id: hoveredID),
                   let row = matrix.rows.firstIndex(where: { $0.id == cell.rowID }),
                   let column = matrix.columns.firstIndex(where: { $0.id == cell.effort }) {
                    let width = min(236, geometry.size.width)
                    let x = min(max(0, modelWidth + CGFloat(column) * cellWidth - width / 2 + cellWidth / 2), geometry.size.width - width)
                    scoreTooltip(cell)
                        .frame(width: width)
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(x: x, y: row >= 2 ? max(0, CGFloat(row) * 30 - 110) : CGFloat(row) * 30 + 52)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: Self.height(rowCount: matrix.rows.count))
    }

    private func scoreTooltip(_ cell: CodexRadarMatrixCell) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(cell.displayName).font(.system(size: 10, weight: .semibold))
                Spacer(minLength: 4)
                if let rank = matrix.rank(of: cell) {
                    Text(L.zh ? "第 \(rank) 名" : "Rank \(rank)")
                        .font(.system(size: 9, weight: .medium))
                }
            }
            Text("\(L.zh ? "原始 IQ" : "Raw IQ") \(String(format: "%.2f", cell.score))")
                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
            Text(L.zh ? "排名使用未取整分数；表格显示整数，因此相同整数可能有不同名次。" : "Ranks use unrounded scores. Equal displayed integers can have different ranks.")
                .font(.system(size: 9)).foregroundStyle(.secondary)
            Text(L.zh ? "综合分按软件工程与视觉空间推理的有效题量加权。" : "Overall IQ weights coding and spatial reasoning by valid task counts.")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(9)
        .background(PopupLayout.background, in: RoundedRectangle(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).stroke(.primary.opacity(0.12), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
    }

    private func score(_ cell: CodexRadarMatrixCell?, row: CodexRadarMatrixRow, effort: String) -> some View {
        let rank = cell.flatMap { matrix.rank(of: $0) }
        let podium = rank.map { $0 <= 3 } ?? false
        return Group {
            if let cell {
                VStack(spacing: 0) {
                    HStack(spacing: 1) {
                        Spacer(minLength: 0)
                        if let rank, rank <= 3 {
                            Image(systemName: "crown.fill").font(.system(size: 7, weight: .semibold))
                            Text("\(rank)").font(.system(size: 7, weight: .bold, design: .rounded))
                        }
                    }
                    .foregroundStyle(rankColor(rank)).frame(height: 9)
                    .padding(.trailing, 3).accessibilityHidden(true)
                    AnimatedMetric(value: cell.score)
                        .font(.system(size: 11, weight: podium ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(podium ? rankColor(rank) : Color.primary)
                        .lineLimit(1).minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.bottom, 2)
                .background {
                    let hovered = hoveredID == cell.id
                    let tint = podium ? rankColor(rank) : Color.primary
                    let opacity = podium ? (colorScheme == .dark ? 0.22 : 0.16) : 0.035
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [tint.opacity(opacity + (hovered ? 0.04 : 0)),
                                                      tint.opacity(opacity * 0.65 + (hovered ? 0.04 : 0))],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay {
                            if podium {
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(tint.opacity(0.3), lineWidth: 0.5)
                            }
                        }
                        .padding(.horizontal, 1)
                }
                .contentShape(Rectangle())
                .onHover { hoveredID = $0 ? cell.id : nil }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L.modelQualityCellAccessibility(
                    model: cell.displayName, score: String(format: "%.2f", cell.score),
                    passCount: nil, rank: rank))
            } else {
                Text("—").font(.system(size: 11)).foregroundStyle(.tertiary)
                    .help(L.zh ? "\(row.displayName) \(effort)：暂无有效数据" : "\(row.displayName) \(effort): no valid data")
            }
        }
    }

    private func rankColor(_ rank: Int?) -> Color {
        let dark = colorScheme == .dark
        switch rank {
        case 1: return dark ? Color(red: 0.98, green: 0.76, blue: 0.28) : Color(red: 0.66, green: 0.43, blue: 0.03)
        case 2: return dark ? Color(red: 0.72, green: 0.80, blue: 0.92) : Color(red: 0.32, green: 0.40, blue: 0.51)
        default: return dark ? Color(red: 0.94, green: 0.63, blue: 0.42) : Color(red: 0.62, green: 0.32, blue: 0.16)
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
    private let infoAccent = Color.accentColor

    var body: some View {
        let _ = language.identity
        if let resetWindow {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(infoAccent)
                Text(L.zh ? "速蹬窗口" : "Speedrun")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(infoAccent)
                HStack(spacing: 3) {
                    Circle().fill(CodexStatusPalette.ok).frame(width: 4, height: 4)
                    Text(L.zh ? "已开启" : "Open")
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(CodexStatusPalette.ok)
                if let expectedResetAt = resetWindow.expectedResetAt {
                    Rectangle().fill(.primary.opacity(0.12)).frame(width: 0.5, height: 12)
                        .padding(.horizontal, 2)
                    Text(L.zh ? "预计重置" : "Est. reset")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                    Text(formattedResetDate(expectedResetAt))
                        .font(.system(size: 10, weight: .medium)).monospacedDigit()
                        .foregroundStyle(.primary)
                        .help("\(L.zh ? "预计重置" : "Expected reset"): \(formattedResetDate(expectedResetAt))")
                        .accessibilityLabel("\(L.zh ? "预计重置" : "Expected reset"): \(formattedResetDate(expectedResetAt))")
                }
                Button {
                    NSWorkspace.shared.open(resetWindow.sourceURL ?? radar.homepageURL)
                } label: {
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium))
                        .frame(width: 16, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusable(false).focusEffectDisabled()
                .foregroundStyle(.secondary)
                .help(L.codexResetWindowSourceHelp)
                .accessibilityLabel(L.codexResetWindowSourceHelp)
            }
            .lineLimit(1)
            .padding(.leading, 8).padding(.trailing, 5).frame(height: 26)
            .popupGlass(radius: PopupControlMetrics.radius, tint: infoAccent.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: PopupControlMetrics.radius)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.06), .primary.opacity(0.08)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .fixedSize(horizontal: true, vertical: false)
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

    private func formattedResetDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L.zh ? "zh_CN" : "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = L.zh ? "M/d HH:mm" : "MMM d HH:mm"
        return formatter.string(from: date)
    }
}
