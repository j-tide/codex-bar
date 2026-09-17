// Rebuild with:
// swiftc codexBar/Support/CodexBrandMark.swift scripts/generate-app-icon.swift -o /tmp/codexbar-icon-generator
// /tmp/codexbar-icon-generator codexBar/Assets.xcassets/AppIcon.appiconset /tmp/codexbar-icon-preview.png
import AppKit

@main
struct GenerateAppIcon {
    static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    static func bitmap(width: Int, height: Int, draw: (CGContext) -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: width * 4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        let graphics = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = graphics
        draw(graphics.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func drawAppIcon(_ context: CGContext, size: CGFloat) {
        context.saveGState()
        defer { context.restoreGState() }
        context.scaleBy(x: size / 1024, y: size / 1024)
        let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
                                xRadius: 188, yRadius: 188)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color(7, 19, 28, 0.28)
        shadow.shadowBlurRadius = 26
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        color(20, 34, 45).setFill()
        body.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(colors: [color(14, 28, 38), color(37, 60, 74)])!.draw(in: body, angle: 90)
        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        let light = NSGradient(starting: color(121, 229, 224, 0.12), ending: .clear)!
        light.draw(fromCenter: NSPoint(x: 350, y: 960), radius: 0,
                   toCenter: NSPoint(x: 350, y: 960), radius: 800, options: [])
        NSGraphicsContext.restoreGraphicsState()
        color(222, 247, 255, 0.22).setStroke()
        body.lineWidth = 2
        body.stroke()
        // Keep the mark flat and high contrast; no miniature dashboard details.
        CodexBrandMark.draw(in: context, rect: CGRect(x: 210, y: 210, width: 604, height: 604),
                            ring: color(99, 226, 199), tasks: color(240, 250, 252))
    }

    static func main() throws {
        guard CommandLine.arguments.count >= 2 else {
            fatalError("Supply an asset output directory and optionally a preview PNG path")
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for size in [16, 32, 64, 128, 256, 512, 1024] {
            let rep = bitmap(width: size, height: size) { drawAppIcon($0, size: CGFloat(size)) }
            try rep.representation(using: .png, properties: [:])!.write(
                to: output.appendingPathComponent("icon_\(size).png"))
        }
        if CommandLine.arguments.count > 2 {
            let preview = bitmap(width: 1000, height: 500) { context in
                color(237, 241, 245).setFill()
                NSRect(x: 0, y: 0, width: 1000, height: 500).fill()
                context.saveGState()
                context.translateBy(x: 36, y: 50)
                drawAppIcon(context, size: 400)
                context.restoreGState()
                let title: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
                    .foregroundColor: color(30, 46, 56)]
                ("codex-bar" as NSString).draw(at: NSPoint(x: 480, y: 358), withAttributes: title)
                let caption: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 17), .foregroundColor: color(93, 111, 123)]
                ("额度监控 · 并行任务" as NSString).draw(at: NSPoint(x: 480, y: 318), withAttributes: caption)
                color(32, 44, 55).setFill()
                NSBezierPath(roundedRect: NSRect(x: 480, y: 220, width: 448, height: 58),
                             xRadius: 18, yRadius: 18).fill()
                CodexBrandMark.draw(in: context, rect: CGRect(x: 502, y: 237, width: 24, height: 24),
                                    ring: .white, tasks: .white)
                let menuFont: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor.white]
                ("7d" as NSString).draw(at: NSPoint(x: 542, y: 236), withAttributes: menuFont)
                color(78, 91, 102).setFill()
                NSBezierPath(roundedRect: NSRect(x: 580, y: 244, width: 80, height: 8), xRadius: 4, yRadius: 4).fill()
                color(60, 214, 161).setFill()
                NSBezierPath(roundedRect: NSRect(x: 580, y: 244, width: 60, height: 8), xRadius: 4, yRadius: 4).fill()
                ("75%   │   ◔ 3   ✓ 1" as NSString).draw(at: NSPoint(x: 674, y: 236), withAttributes: menuFont)
                ("菜单栏原尺寸" as NSString).draw(at: NSPoint(x: 480, y: 161), withAttributes: caption)
                color(32, 44, 55).setFill()
                NSBezierPath(roundedRect: NSRect(x: 620, y: 158, width: 48, height: 26), xRadius: 8, yRadius: 8).fill()
                CodexBrandMark.draw(in: context, rect: CGRect(x: 636, y: 163, width: 16, height: 16),
                                    ring: .white, tasks: .white)
            }
            try preview.representation(using: .png, properties: [:])!.write(
                to: URL(fileURLWithPath: CommandLine.arguments[2]))
        }
    }
}
