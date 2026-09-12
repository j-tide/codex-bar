import SwiftUI

private struct PopupArrowKey: EnvironmentKey { static let defaultValue: CGFloat? = nil }
extension EnvironmentValues {
    var popupArrowX: CGFloat? {
        get { self[PopupArrowKey.self] }
        set { self[PopupArrowKey.self] = newValue }
    }
}

struct PopupGlassOutline: Shape {
    var arrowX: CGFloat?
    var radius: CGFloat = 20
    static let arrowHeight: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        guard let arrowX else { return RoundedRectangle(cornerRadius: radius).path(in: rect) }
        let top = rect.minY + Self.arrowHeight
        let left = rect.minX, right = rect.maxX, bottom = rect.maxY
        let r = min(radius, rect.width / 2, max(0, (rect.height - Self.arrowHeight) / 2))
        let x = min(max(rect.minX + arrowX, left + r + 14), right - r - 14)
        return Path { p in
            p.move(to: CGPoint(x: left + r, y: top))
            p.addLine(to: CGPoint(x: x - 14, y: top))
            p.addQuadCurve(to: CGPoint(x: x - 9, y: top - 3), control: CGPoint(x: x - 11, y: top))
            p.addLine(to: CGPoint(x: x - 3, y: rect.minY + 2))
            p.addQuadCurve(to: CGPoint(x: x + 3, y: rect.minY + 2), control: CGPoint(x: x, y: rect.minY - 1))
            p.addLine(to: CGPoint(x: x + 9, y: top - 3))
            p.addQuadCurve(to: CGPoint(x: x + 14, y: top), control: CGPoint(x: x + 11, y: top))
            p.addLine(to: CGPoint(x: right - r, y: top))
            p.addQuadCurve(to: CGPoint(x: right, y: top + r), control: CGPoint(x: right, y: top))
            p.addLine(to: CGPoint(x: right, y: bottom - r))
            p.addQuadCurve(to: CGPoint(x: right - r, y: bottom), control: CGPoint(x: right, y: bottom))
            p.addLine(to: CGPoint(x: left + r, y: bottom))
            p.addQuadCurve(to: CGPoint(x: left, y: bottom - r), control: CGPoint(x: left, y: bottom))
            p.addLine(to: CGPoint(x: left, y: top + r))
            p.addQuadCurve(to: CGPoint(x: left + r, y: top), control: CGPoint(x: left, y: top))
            p.closeSubpath()
        }
    }
}

/// Keep one native rendering container for the popup's glass surfaces and controls.
struct PopupGlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) { content() }
        } else {
            content()
        }
    }
}

private struct PopupGlassSurface: ViewModifier {
    let radius: CGFloat
    let tint: Color?
    let interactive: Bool
    let arrowX: CGFloat?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        let outline = PopupGlassOutline(arrowX: arrowX, radius: radius)
        if reduceTransparency {
            content.background(PopupLayout.background, in: outline)
        } else if #available(macOS 26.0, *) {
            if let tint {
                content.glassEffect(.regular.tint(tint).interactive(interactive), in: outline)
            } else {
                content.glassEffect(.regular.interactive(interactive), in: outline)
            }
        } else {
            content.background(.regularMaterial, in: outline)
        }
    }
}

enum PopupControlMetrics {
    static let radius: CGFloat = 10
    static let compactRadius: CGFloat = 7
    static let selectionRadius: CGFloat = 6
}

private struct PopupGlassControlStyle: ButtonStyle {
    var tint: Color?
    var compact: Bool
    var iconOnly: Bool
    var busy: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var radius: CGFloat { compact ? PopupControlMetrics.compactRadius : PopupControlMetrics.radius }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint ?? .primary)
            // Icon controls match the neighboring 26-point settings strip.
            .frame(width: iconOnly ? 18 : nil, height: iconOnly ? 18 : nil)
            .padding(.horizontal, iconOnly || compact ? 6 : 10)
            .padding(.vertical, iconOnly ? 4 : compact ? 2 : 3)
            .contentShape(.interaction, RoundedRectangle(cornerRadius: radius))
            .popupGlass(radius: radius, tint: busy ? PopupLayout.accent.opacity(0.10) : tint?.opacity(0.12), interactive: true)
            // Busy controls reject repeat clicks, but their progress stays legible.
            .opacity(isEnabled || busy ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    func popupGlass(radius: CGFloat = PopupControlMetrics.radius, tint: Color? = nil, interactive: Bool = false, arrowX: CGFloat? = nil) -> some View {
        modifier(PopupGlassSurface(radius: radius, tint: tint, interactive: interactive, arrowX: arrowX))
    }

    func popupGlassButton(tint: Color? = nil, compact: Bool = false, iconOnly: Bool = false, busy: Bool = false) -> some View {
        // The material has an older-system fallback, but its contour and input
        // shape stay identical to the native-glass version.
        self.buttonStyle(PopupGlassControlStyle(tint: tint, compact: compact, iconOnly: iconOnly, busy: busy))
            .controlSize(.small).focusable(false).focusEffectDisabled()
    }
}
