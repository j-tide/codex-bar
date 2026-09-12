import AppKit
import SwiftUI

enum CodexStatusPalette {
    private static let okRGB = (red: 0.02, green: 0.62, blue: 0.33)
    private static let warningRGB = (red: 0.76, green: 0.46, blue: 0.03)
    private static let dangerRGB = (red: 0.84, green: 0.25, blue: 0.15)
    private static let unavailableRGB = (red: 0.78, green: 0.16, blue: 0.22)

    static let ok = color(okRGB)
    static let warning = color(warningRGB)
    static let runningNSColor = NSColor.systemYellow
    // Keep the yellow state identity while giving small text enough contrast
    // on light glass. The menu bar retains its system-provided yellow.
    static let running = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return .systemYellow
        }
        return NSColor(calibratedRed: 0.55, green: 0.40, blue: 0.02, alpha: 1)
    })
    static let brightWarning = Color(red: 0.98, green: 0.62, blue: 0.04)
    static let danger = color(dangerRGB)
    static let unavailable = color(unavailableRGB)

    static func color(for status: UsageStatus) -> Color {
        switch status {
        case .ok: return ok
        case .warning: return warning
        case .exceeded: return danger
        case .banned: return unavailable
        }
    }

    static func color(forUsedPercent usedPercent: Double) -> Color {
        if usedPercent >= 90 { return danger }
        if usedPercent >= 70 { return warning }
        return ok
    }

    // Menu bar fills keep their saturated colors regardless of the popup appearance.
    static func menuBarColor(forUsedPercent usedPercent: Double) -> NSColor {
        let rgb = usedPercent >= 90 ? dangerRGB : usedPercent >= 70 ? warningRGB : okRGB
        return NSColor(calibratedRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    private static func color(_ rgb: (red: Double, green: Double, blue: Double)) -> Color {
        Color(nsColor: nsColor(rgb))
    }

    private static func nsColor(_ rgb: (red: Double, green: Double, blue: Double)) -> NSColor {
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value: (red: Double, green: Double, blue: Double)
            if !dark { value = rgb }
            else if rgb == okRGB { value = (0.408, 0.827, 0.627) }
            else if rgb == warningRGB { value = (0.910, 0.722, 0.337) }
            else { value = (0.980, 0.569, 0.522) }
            return NSColor(calibratedRed: value.red, green: value.green, blue: value.blue, alpha: 1)
        }
    }
}
