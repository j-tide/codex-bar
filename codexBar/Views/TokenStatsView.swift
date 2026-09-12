import SwiftUI

struct TokenStatsView: View {
    @Environment(\.popupLiveUpdates) private var liveUpdates
    @EnvironmentObject var language: LanguageSettings
    @ObservedObject var service: TokenStatsService = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    if let stat = service.stat {
                        AnimatedMetric(value: Double(stat.totalTokens), format: .tokens)
                            .font(.system(size: 23, weight: .medium)).foregroundStyle(Color.accentColor)
                    } else {
                        Text(service.loading ? (L.zh ? "正在读取…" : "Loading…") : (L.zh ? "暂无用量数据" : "Usage unavailable"))
                            .font(.system(size: 12)).foregroundStyle(.secondary).frame(height: 28)
                    }
                    Text("\(service.range.label) · \(L.tokenTotal)").font(.system(size: 10)).foregroundStyle(.secondary)
                        .help(L.zh ? "按本地日期累计的输入与输出 Token，包含缓存输入；统计此设备的 Codex 会话" : "Input and output tokens by local date, including cached input; Codex sessions on this device")
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    TokenRangeSegmentedControl(selection: Binding(
                        get: { service.range }, set: { service.switchTo($0) }
                    )).id(language.identity)
                    HStack(spacing: 5) {
                        if service.loading { ProgressView().controlSize(.mini) }
                        Text(service.stat.map { L.tokenThreadCount($0.threadCount) } ?? "")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
            Divider().padding(.top, 2)
            HStack {
                Text(L.zh ? "用量趋势" : "Usage history")
                    .font(.system(size: 10, weight: .medium))
                Spacer()
                Text(L.zh ? "固定时间范围" : "Fixed date ranges")
                    .font(.system(size: 8)).foregroundStyle(.secondary)
            }
            TokenUsageHistoryView(daily: service.daily)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .task {
            guard liveUpdates else { return }
            // Render cached content first and avoid competing with first layout.
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            service.refreshIfNeeded()
        }
    }


}

private struct TokenRangeSegmentedControl: View {
    @Namespace private var selectionMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: TokenStatsRange

    private var controlWidth: CGFloat { L.zh ? 138 : 174 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TokenStatsRange.allCases) { range in
                let selected = selection == range
                Button { selection = range } label: {
                    Text(L.zh ? range.label : (range == .today ? "Today" : range == .week ? "Week" : "Month"))
                        .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.76))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity).frame(height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusable(false).focusEffectDisabled()
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: PopupControlMetrics.selectionRadius)
                            .fill(Color.accentColor.opacity(0.18))
                            .matchedGeometryEffect(id: "period-selection", in: selectionMotion)
                    }
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3).frame(width: controlWidth, height: 30)
        .popupGlass()
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: selection)
    }
}

enum TokenFormat {
    /// zh: 12345 -> "1.2万", 2160000000 -> "21.6亿"
    /// en: 1234 -> "1.2K", 1234567 -> "1.2M", 1234000000 -> "1.2B"
    static func compact(_ n: Int) -> String {
        if L.zh { return compactChinese(n) }

        let v = Double(n)
        switch n {
        case 1_000_000_000...:
            return format(v / 1_000_000_000, suffix: "B", decimals: 1)
        case 1_000_000...:
            return format(v / 1_000_000, suffix: "M", decimals: 1)
        case 1_000...:
            return format(v / 1_000, suffix: "K", decimals: 1)
        default:
            return "\(n)"
        }
    }

    private static func compactChinese(_ n: Int) -> String {
        let v = Double(n)
        switch n {
        case 100_000_000...:
            return format(v / 100_000_000, suffix: "亿", decimals: 1)
        case 10_000...:
            return format(v / 10_000, suffix: "万", decimals: 1)
        default:
            return "\(n)"
        }
    }

    private static func format(_ value: Double, suffix: String, decimals: Int) -> String {
        var text = String(format: "%.\(decimals)f", value)
        while text.contains("."), text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text + suffix
    }
}
