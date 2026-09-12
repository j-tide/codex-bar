import SwiftUI

/// Local, cancellable entrance effects; previews and Reduce Motion stay fully visible.
private struct PopupEntrance: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.popupLiveUpdates) private var liveUpdates
    @State private var entered = false
    private var visible: Bool { entered || reduceMotion || !liveUpdates }

    func body(content: Content) -> some View {
        content.opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 6)
            .task {
                guard liveUpdates, !reduceMotion else { return }
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.88).delay(delay)) { entered = true }
            }
            .onDisappear { entered = false }
    }
}

extension View {
    func popupEntrance(delay: Double = 0) -> some View { modifier(PopupEntrance(delay: delay)) }
}

struct PopupThemeOriginKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// A brief illumination wave from the appearance control; no duplicated panel.
private struct PopupThemeWave: ViewModifier {
    let dark: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(PopupThemeOriginKey.self) { anchor in
            if let startedAt, !reduceMotion {
                TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                    let progress = min(1, max(0, context.date.timeIntervalSince(startedAt) / 0.6))
                    GeometryReader { geometry in
                        let origin = anchor.map { geometry[$0] } ?? CGRect(x: geometry.size.width - 64, y: geometry.size.height - 22, width: 0, height: 0)
                        let travel = 1 - pow(1 - progress, 2)
                        let radius = hypot(geometry.size.width, geometry.size.height) * (dark ? 1 - travel : travel)
                        let color = dark ? Color(red: 0.48, green: 0.57, blue: 1) : Color(red: 1, green: 0.79, blue: 0.43)
                        ZStack {
                            Circle().fill(RadialGradient(colors: [.clear, color.opacity(0.02), color.opacity(0.2), .clear],
                                center: .center, startRadius: max(0, radius - 100), endRadius: max(1, radius)))
                            Circle().strokeBorder(color.opacity(0.4), lineWidth: 1.5).blur(radius: 1)
                        }
                        .frame(width: radius * 2, height: radius * 2)
                        .position(x: origin.midX, y: origin.midY)
                        .opacity(pow(sin(progress * .pi), 0.6))
                    }
                }
                .allowsHitTesting(false).accessibilityHidden(true)
                .task(id: startedAt) {
                    try? await Task.sleep(for: .milliseconds(650))
                    guard !Task.isCancelled else { return }
                    self.startedAt = nil
                }
            }
        }
        .onChange(of: dark) { _, _ in startedAt = reduceMotion ? nil : Date() }
        .onDisappear { startedAt = nil }
    }
}

extension View {
    func popupThemeWave(dark: Bool) -> some View { modifier(PopupThemeWave(dark: dark)) }
}

enum MetricFormat {
    case tokens, integer, percent
    func text(_ value: Double) -> String {
        switch self {
        case .tokens: return TokenFormat.compact(Int(value.rounded()))
        case .integer: return String(Int(value.rounded()))
        case .percent: return "\(Int(value.rounded()))%"
        }
    }
}

/// Preserve the original numericText digit roll and 0.25-second easing.
/// Formatting jumps directly to the real value; no synthetic intermediate counts.
struct AnimatedMetric: View {
    @AppStorage("languageOverride") private var chinese = L.systemIsChinese
    let value: Double?
    var format: MetricFormat = .integer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.popupLiveUpdates) private var liveUpdates
    @State private var displayed: Double?

    var body: some View {
        let _ = chinese
        let visibleValue = reduceMotion || !liveUpdates ? value : (displayed ?? value)
        Text(visibleValue.map(format.text) ?? "--")
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(reduceMotion || !liveUpdates ? nil : .easeOut(duration: 0.25), value: displayed)
            .accessibilityLabel(value.map(format.text) ?? "--")
            .task(id: value) {
                guard liveUpdates, !reduceMotion else { displayed = value; return }
                if displayed == nil, value != nil {
                    try? await Task.sleep(for: .milliseconds(40))
                    guard !Task.isCancelled else { return }
                }
                displayed = value
            }
            .onDisappear { displayed = nil }
    }
}
