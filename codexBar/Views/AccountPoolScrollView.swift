import SwiftUI

struct AccountAvailabilitySummary: View {
    @EnvironmentObject private var language: LanguageSettings
    let available: Int
    let unavailable: Int

    private var tint: Color {
        unavailable > 0 ? CodexStatusPalette.unavailable : available > 0 ? CodexStatusPalette.ok : .secondary
    }

    var body: some View {
        let _ = language.identity
        HStack(spacing: 5) {
            if unavailable > 0 {
                Text(L.zh ? "\(available) 可用" : "\(available) available")
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Image(systemName: "exclamationmark.circle.fill")
                Text(L.zh ? "\(unavailable) 不可用" : "\(unavailable) unavailable")
                    .fontWeight(.semibold)
            } else if available > 0 {
                Image(systemName: "checkmark.circle.fill")
                Text(L.zh ? "全部可用" : "All available")
                Text("·").opacity(0.5)
                Text("\(available)").fontWeight(.semibold)
            } else {
                Image(systemName: "person.crop.circle")
                Text(L.zh ? "暂无账号" : "No accounts")
            }
        }
        .font(.system(size: 10, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(tint)
        .padding(.horizontal, 8).frame(height: 25)
        .popupGlass(radius: PopupControlMetrics.compactRadius, tint: tint.opacity(unavailable > 0 ? 0.10 : 0.06))
        .fixedSize()
        .accessibilityElement(children: .combine)
        .help(L.zh ? "不可用包括授权失效、账号受限或额度耗尽" : "Unavailable includes expired authorization, restricted accounts, or exhausted quota")
    }

}

/// Persistent scroll cues stay visible even when macOS hides its overlay scrollers.
struct AccountPoolScrollView<Content: View>: View {
    @EnvironmentObject private var language: LanguageSettings
    let accountCount: Int
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position = ScrollPosition(edge: .top)
    @State private var metrics = Metrics()

    private struct Metrics: Equatable {
        var offset: CGFloat = 0
        var viewport: CGFloat = 0
        var content: CGFloat = 0
        var maximum: CGFloat { max(0, content - viewport) }
        var canScroll: Bool { maximum > 1 }
        var canGoUp: Bool { offset > 1 }
        var canGoDown: Bool { offset < maximum - 1 }
    }

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.vertical) {
                content().padding(.trailing, 12)
            }
            .scrollIndicators(.hidden)
            .scrollPosition($position)
            .onScrollGeometryChange(for: Metrics.self) { geometry in
                Metrics(offset: max(0, geometry.contentOffset.y + geometry.contentInsets.top).rounded(),
                        viewport: geometry.containerSize.height.rounded(),
                        content: geometry.contentSize.height.rounded())
            } action: { _, value in
                metrics = value
            }
            .overlay(alignment: .trailing) {
                if metrics.canScroll { scrollRail.allowsHitTesting(false).accessibilityHidden(true) }
            }

            if metrics.canScroll {
                HStack(spacing: 5) {
                    Image(systemName: metrics.canGoDown ? "arrow.down" : "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                    Text(L.zh ? "其他 \(accountCount) 个账号" : "\(accountCount) other accounts")
                    Text("·").foregroundStyle(.tertiary)
                    Text(metrics.canGoDown ? (L.zh ? "下滑查看更多" : "Scroll for more") : (L.zh ? "已到底部" : "End of list"))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    scrollButton(up: true)
                    scrollButton(up: false)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(PopupLayout.accent)
                .padding(.top, 4)
                .overlay(alignment: .top) { Rectangle().fill(.primary.opacity(0.08)).frame(height: 0.5) }
            }
        }
    }

    private var scrollRail: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let thumb = min(height, max(24, height * metrics.viewport / max(1, metrics.content)))
            let offset = (height - thumb) * min(1, metrics.offset / max(1, metrics.maximum))
            ZStack(alignment: .top) {
                Capsule().fill(.primary.opacity(0.07))
                Capsule().fill(.secondary.opacity(0.55)).frame(height: thumb).offset(y: offset)
            }
        }.frame(width: 4).padding(.trailing, 1)
    }

    private func scrollButton(up: Bool) -> some View {
        Button {
            let distance = max(40, metrics.viewport * 0.8) * (up ? -1 : 1)
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                position.scrollTo(y: min(metrics.maximum, max(0, metrics.offset + distance)))
            }
        } label: {
            Image(systemName: up ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .popupGlassButton(compact: true, iconOnly: true)
        .disabled(up ? !metrics.canGoUp : !metrics.canGoDown)
        .help(up ? (L.zh ? "向上翻看账号" : "Scroll accounts up") : (L.zh ? "向下翻看账号" : "Scroll accounts down"))
        .accessibilityLabel(up ? (L.zh ? "向上翻看账号" : "Scroll accounts up") : (L.zh ? "向下翻看账号" : "Scroll accounts down"))
    }
}
