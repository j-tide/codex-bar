import AppKit

/// A quota ring surrounding parallel tasks. Shared by the app and menu bar icons.
enum CodexBrandMark {
    static let menuImage: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: context, rect: rect,
                 ring: NSColor.white.withAlphaComponent(0.93),
                 tasks: NSColor.white.withAlphaComponent(0.93))
            return true
        }
        image.accessibilityDescription = "codex-bar"
        return image
    }()

    static func draw(in context: CGContext, rect: CGRect, ring: NSColor, tasks: NSColor) {
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / 16, y: rect.height / 16)
        context.setLineCap(.round)
        context.setLineWidth(1.65)
        context.setStrokeColor(ring.cgColor)
        context.addArc(center: CGPoint(x: 7.25, y: 8), radius: 6,
                       startAngle: .pi * 50 / 180, endAngle: .pi * 310 / 180,
                       clockwise: false)
        context.strokePath()
        context.setStrokeColor(tasks.cgColor)
        for (y, end): (CGFloat, CGFloat) in [(10.7, 14.6), (8, 12.5), (5.3, 14.6)] {
            context.move(to: CGPoint(x: 6.8, y: y))
            context.addLine(to: CGPoint(x: end, y: y))
        }
        context.strokePath()
    }
}
