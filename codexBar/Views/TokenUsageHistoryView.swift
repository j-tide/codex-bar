import SwiftUI

struct TokenUsageDay: Identifiable {
    let date: Date
    let tokens: Int
    var id: Date { date }

    static func series(daily: [String: Int], now: Date = Date()) -> [Self] {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: now)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return (0..<30).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
            .map { Self(date: $0, tokens: max(0, daily[formatter.string(from: $0)] ?? 0)) }
    }
}

/// The calendar shows 16 weeks; the curve focuses on the latest 30 local calendar days.
struct TokenUsageHistoryView: View {
    @AppStorage("languageOverride") private var chinese = L.systemIsChinese
    let daily: [String: Int]
    @State private var hoveredDay: TokenUsageDay?

    var body: some View {
        let _ = chinese
        let series = TokenUsageDay.series(daily: daily)
        GeometryReader { geometry in
            // Compact rows and shared full-width edges give the curve equal visual weight.
            let cellWidth = max(1, (geometry.size.width - 45) / 16)
            let cellHeight = max(5, min(8, (geometry.size.height * 0.44 - 18) / 7))
            VStack(spacing: 6) {
                ContributionHeatmap(daily: daily, cellSize: cellWidth, cellHeight: cellHeight)
                HStack {
                    Text(L.zh ? "最近 16 周 · 每日用量" : "Last 16 weeks · daily tokens")
                    Spacer(minLength: 4)
                    HStack(spacing: 2) {
                        ForEach(0..<5) { level in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(ContributionHeatmap.color(level)).frame(width: 5, height: 5)
                        }
                    }
                }
                .font(.system(size: 8)).foregroundStyle(.secondary)

                HStack {
                    Text(L.zh ? "最近 30 天 · 每日用量" : "Last 30 days · daily tokens")
                    Spacer()
                }.font(.system(size: 8)).foregroundStyle(.secondary)

                TokenUsageCurve(series: series, hoveredDay: $hoveredDay)
                    .frame(maxHeight: .infinity)

                HStack {
                    if let hoveredDay {
                        Text(hoveredDay.date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                        Spacer(minLength: 4)
                        Text("\(TokenFormat.compact(hoveredDay.tokens)) tokens")
                    } else {
                        if let start = series.first?.date {
                            Text(start, format: .dateTime.month(.twoDigits).day(.twoDigits))
                        }
                        Spacer(minLength: 4)
                        Text("\(L.zh ? "峰值" : "Peak") \(TokenFormat.compact(series.map(\.tokens).max() ?? 0))")
                        Spacer(minLength: 4)
                        Text(L.zh ? "今日" : "Today")
                    }
                }
                .font(.system(size: 8)).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct TokenUsageCurve: View {
    @AppStorage("languageOverride") private var chinese = L.systemIsChinese
    let series: [TokenUsageDay]
    @Binding var hoveredDay: TokenUsageDay?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.popupLiveUpdates) private var liveUpdates
    @State private var revealed = false

    var body: some View {
        let _ = chinese
        GeometryReader { geometry in
            let size = geometry.size
            let maximum = max(1, series.map(\.tokens).max() ?? 0)
            let points = series.enumerated().map { index, day in
                CGPoint(x: CGFloat(index) / CGFloat(max(series.count - 1, 1)) * size.width,
                        y: 3 + (1 - CGFloat(day.tokens) / CGFloat(maximum)) * max(0, size.height - 6))
            }
            let line = TokenCurvePath.smooth(points)
            ZStack(alignment: .topLeading) {
                Path { path in
                    for fraction in [CGFloat(0), 0.5, 1] {
                        let y = 3 + fraction * max(0, size.height - 6)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                }
                .stroke(Color.primary.opacity(0.09), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))

                Path { path in
                    guard let first = points.first, let last = points.last else { return }
                    path.addPath(line)
                    path.addLine(to: CGPoint(x: last.x, y: size.height - 3))
                    path.addLine(to: CGPoint(x: first.x, y: size.height - 3))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color.accentColor.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom))
                line.trim(from: 0, to: revealed || reduceMotion || !liveUpdates ? 1 : 0)
                    .stroke(Color.accentColor.opacity(0.9), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))

                if let hoveredDay, let index = series.firstIndex(where: { $0.id == hoveredDay.id }) {
                    let point = points[index]
                    Path { path in
                        path.move(to: CGPoint(x: point.x, y: 0))
                        path.addLine(to: CGPoint(x: point.x, y: size.height))
                    }.stroke(Color.accentColor.opacity(0.35), lineWidth: 0.5)
                    Circle().fill(Color.accentColor).frame(width: 4, height: 4).position(point)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard !series.isEmpty, size.width > 0 else { return }
                    let index = min(series.count - 1, max(0, Int((location.x / size.width * CGFloat(series.count - 1)).rounded())))
                    hoveredDay = series[index]
                case .ended: hoveredDay = nil
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.zh ? "最近 30 天每日 Token 用量曲线" : "Daily token usage over the last 30 days")
        .accessibilityValue(L.zh ? "峰值 \(TokenFormat.compact(series.map(\.tokens).max() ?? 0)) tokens" : "Peak \(TokenFormat.compact(series.map(\.tokens).max() ?? 0)) tokens")
        .task {
            guard liveUpdates, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.6)) { revealed = true }
        }
        .onDisappear { revealed = false; hoveredDay = nil }
    }
}

/// Monotone cubic interpolation preserves measured points and local extrema.
enum TokenCurvePath {
    static func smooth(_ points: [CGPoint]) -> Path {
        guard points.count > 1 else {
            return Path { if let point = points.first { $0.move(to: point) } }
        }
        let slopes = zip(points, points.dropFirst()).map { a, b in
            (b.y - a.y) / max(b.x - a.x, 0.0001)
        }
        var tangents = Array(repeating: CGFloat.zero, count: points.count)
        tangents[0] = slopes[0]
        tangents[points.count - 1] = slopes[slopes.count - 1]
        for i in 1..<(points.count - 1) where slopes[i - 1] * slopes[i] > 0 {
            tangents[i] = 2 / (1 / slopes[i - 1] + 1 / slopes[i])
        }
        return Path { path in
            path.move(to: points[0])
            for i in 0..<(points.count - 1) {
                let a = points[i], b = points[i + 1]
                let dx = (b.x - a.x) / 3
                path.addCurve(to: b,
                    control1: CGPoint(x: a.x + dx, y: a.y + tangents[i] * dx),
                    control2: CGPoint(x: b.x - dx, y: b.y - tangents[i + 1] * dx))
            }
        }
    }
}
