import SwiftUI

/// GitHub 风格贡献热力图：展示最近 N 周每天的 token 用量，绿点深浅按对数档位。
struct ContributionHeatmap: View {
    @AppStorage("languageOverride") private var chinese = L.systemIsChinese
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.popupLiveUpdates) private var liveUpdates
    @State private var revealed = false
    private var visible: Bool { revealed || reduceMotion || !liveUpdates }
    let daily: [String: Int]   // "yyyy-MM-dd" -> tokens
    var weeks: Int = 16

    @State private var hoveredCell: HoveredCell?

    // GitHub 风格正方形小格子
    var cellSize: CGFloat = 11
    var cellHeight: CGFloat? = nil
    private var cellW: CGFloat { cellSize }
    private var cellH: CGFloat { cellHeight ?? cellSize }
    private let gap: CGFloat = 3
    private let tooltipWidth: CGFloat = 104
    private let tooltipHeight: CGFloat = 38
    private let tooltipGap: CGFloat = 4

    private struct HoveredCell: Equatable {
        let key: String
        let date: Date
        let column: Int
        let row: Int
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let zhTooltipDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f
    }()

    private static let enTooltipDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    /// 网格起点：今天所在周的周一，往回推 weeks-1 周
    private var columns: [[Date]] { Self.dateColumns(weeks: weeks) }

    static func dateColumns(weeks: Int = 16, now: Date = Date()) -> [[Date]] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // 周一
        let today = cal.startOfDay(for: now)
        let weekday = cal.component(.weekday, from: today)
        let offsetToMon = ((weekday - cal.firstWeekday) + 7) % 7
        guard let thisMon = cal.date(byAdding: .day, value: -offsetToMon, to: today),
              let start = cal.date(byAdding: .day, value: -(weeks - 1) * 7, to: thisMon) else { return [] }

        var cols: [[Date]] = []
        for w in 0..<weeks {
            var col: [Date] = []
            for d in 0..<7 {
                if let day = cal.date(byAdding: .day, value: w * 7 + d, to: start) {
                    col.append(day)
                }
            }
            cols.append(col)
        }
        return cols
    }

    /// 对数档位 0...4
    private func level(_ tokens: Int) -> Int {
        switch tokens {
        case 0: return 0
        case 1..<10_000_000: return 1          // <10M
        case 10_000_000..<100_000_000: return 2 // 10M-100M
        case 100_000_000..<1_000_000_000: return 3 // 100M-1B
        default: return 4                       // >=1B
        }
    }

    /// GitHub 经典 5 档实色梯度（深浅分明，不靠 opacity）
    static func color(_ lvl: Int) -> Color {
        switch lvl {
        case 0: return Color.primary.opacity(0.08) // 空：随深浅主题自适应的低透明度
        case 1: return Color(red: 0.62, green: 0.78, blue: 0.65) // 柔和浅绿
        case 2: return Color(red: 0.42, green: 0.66, blue: 0.48) // 柔和中绿
        case 3: return Color(red: 0.28, green: 0.52, blue: 0.36) // 柔和深绿
        default: return Color(red: 0.18, green: 0.38, blue: 0.26) // 柔和最深绿
        }
    }

    private var gridWidth: CGFloat {
        CGFloat(weeks) * cellW + CGFloat(max(weeks - 1, 0)) * gap
    }

    private var gridHeight: CGFloat {
        7 * cellH + 6 * gap
    }

    var body: some View {
        let _ = chinese
        let today = Calendar(identifier: .gregorian).startOfDay(for: Date())
        let cells = columns.enumerated().flatMap { column, days in
            days.enumerated().map { row, day in
                let key = Self.fmt.string(from: day)
                return HeatmapDrawing.Cell(date: day, key: key, column: column, row: row,
                    level: level(daily[key] ?? 0), isFuture: day > today)
            }
        }
        ZStack(alignment: .topLeading) {
            HeatmapDrawing(cells: cells, cellWidth: cellW, cellHeight: cellH, gap: gap,
                reveal: visible ? 1 : 0, hoveredKey: hoveredCell?.key, reduceMotion: reduceMotion)
                .animation(reduceMotion || !liveUpdates ? nil : .linear(duration: 0.68), value: revealed)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let column = Int(floor(location.x / (cellW + gap)))
                        let row = Int(floor(location.y / (cellH + gap)))
                        let index = column * 7 + row
                        guard column >= 0, column < weeks, row >= 0, row < 7,
                              cells.indices.contains(index), !cells[index].isFuture,
                              location.x - CGFloat(column) * (cellW + gap) <= cellW,
                              location.y - CGFloat(row) * (cellH + gap) <= cellH else {
                            hoveredCell = nil
                            return
                        }
                        let cell = cells[index]
                        if hoveredCell?.key != cell.key {
                            hoveredCell = HoveredCell(key: cell.key, date: cell.date, column: column, row: row)
                        }
                    case .ended: hoveredCell = nil
                    }
                }

            if let hoveredCell {
                usageTooltip(for: hoveredCell)
                    .position(tooltipPosition(for: hoveredCell))
                    .allowsHitTesting(false)
                    .id(hoveredCell.key)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)),
                        removal: .identity
                    ))
                    .zIndex(2)
            }
        }
        .frame(width: gridWidth, height: gridHeight)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredCell)
        .task {
            guard liveUpdates, !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            revealed = true
        }
        .onDisappear { revealed = false; hoveredCell = nil }
    }

    private func usageTooltip(for cell: HoveredCell) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(tooltipDate(cell.date))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(L.tokenDailyUsage(TokenFormat.compact(daily[cell.key] ?? 0)))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .frame(width: tooltipWidth, height: tooltipHeight, alignment: .leading)
        // A transient NSVisualEffect-backed material can change the enclosing
        // glass panel's backdrop composition. Keep the tooltip a local paint layer.
        .background(PopupLayout.background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }

    private func tooltipPosition(for cell: HoveredCell) -> CGPoint {
        let cellCenterX = CGFloat(cell.column) * (cellW + gap) + cellW / 2
        let cellCenterY = CGFloat(cell.row) * (cellH + gap) + cellH / 2
        let halfTooltipWidth = tooltipWidth / 2
        let halfTooltipHeight = tooltipHeight / 2
        let rawY: CGFloat

        if cell.row <= 2 {
            rawY = cellCenterY + cellH / 2 + tooltipGap + halfTooltipHeight
        } else {
            rawY = cellCenterY - cellH / 2 - tooltipGap - halfTooltipHeight
        }

        return CGPoint(
            x: min(max(cellCenterX, halfTooltipWidth), gridWidth - halfTooltipWidth),
            y: min(max(rawY, halfTooltipHeight), gridHeight - halfTooltipHeight)
        )
    }

    private func tooltipDate(_ date: Date) -> String {
        let formatter = L.zh ? Self.zhTooltipDateFormatter : Self.enTooltipDateFormatter
        return formatter.string(from: date)
    }
}

/// One animated surface instead of 112 individually laid-out, hover-tracked views.
private struct HeatmapDrawing: View, Animatable {
    struct Cell {
        let date: Date
        let key: String
        let column: Int
        let row: Int
        let level: Int
        let isFuture: Bool
    }
    let cells: [Cell]
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let gap: CGFloat
    var reveal: Double
    let hoveredKey: String?
    let reduceMotion: Bool
    var animatableData: Double {
        get { reveal }
        set { reveal = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            for cell in cells where !cell.isFuture {
                let delay = Double(cell.column) * 0.018 + Double(cell.row) * 0.012
                let time = max(0, min(1, (reveal * 0.68 - delay) / 0.34))
                let spring = reveal >= 1 ? 1 : 1 - exp(-7 * time) * cos(8 * time)
                let hovered = cell.key == hoveredKey
                let scale = (0.5 + 0.5 * spring) * (hovered && !reduceMotion ? 1.1 : 1)
                let rect = CGRect(x: CGFloat(cell.column) * (cellWidth + gap),
                    y: CGFloat(cell.row) * (cellHeight + gap), width: cellWidth, height: cellHeight)
                let scaled = rect.insetBy(dx: cellWidth * (1 - scale) / 2, dy: cellHeight * (1 - scale) / 2)
                context.opacity = 0.2 + 0.8 * min(1, spring)
                context.fill(Path(roundedRect: scaled, cornerRadius: 2), with: .color(ContributionHeatmap.color(cell.level)))
                if hovered {
                    context.opacity = 1
                    context.stroke(Path(roundedRect: scaled.insetBy(dx: -2, dy: -2), cornerRadius: 3),
                        with: .color(.accentColor), lineWidth: 1.5)
                }
            }
        }
        .accessibilityLabel(L.zh ? "每日 Token 用量热力图" : "Daily token usage heatmap")
    }
}
