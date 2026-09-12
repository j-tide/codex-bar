import AppKit
import SwiftUI
import XCTest
@testable import codexAppBar

@MainActor
final class TokenUsageHistoryTests: XCTestCase {
    func testSmoothedCurvePreservesPeaksAndDoesNotOvershootSegments() {
        let points = [CGPoint(x: 0, y: 90), CGPoint(x: 10, y: 90), CGPoint(x: 20, y: 10),
                      CGPoint(x: 30, y: 70), CGPoint(x: 40, y: 95)]
        var segment = 0
        TokenCurvePath.smooth(points).forEach { element in
            if case let .curve(to: end, control1: c1, control2: c2) = element {
                let start = points[segment]
                XCTAssertEqual(end, points[segment + 1])
                let bounds = min(start.y, end.y)...max(start.y, end.y)
                XCTAssertTrue(bounds.contains(c1.y))
                XCTAssertTrue(bounds.contains(c2.y))
                segment += 1
            }
        }
        XCTAssertEqual(segment, points.count - 1)
    }

    func testHistoryUsesThirtyLocalDaysFillsGapsAndExcludesFuture() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 12)))
        let series = TokenUsageDay.series(daily: ["2026-09-10": 1234, "2026-09-11": 5678,
            "2026-09-12": 9999, "2020-01-01": 1111], now: now)
        XCTAssertEqual(series.first?.date, calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)))
        XCTAssertEqual(series.last?.date, calendar.startOfDay(for: now))
        XCTAssertEqual(series.count, 30)
        XCTAssertEqual(series.suffix(2).map(\.tokens), [1234, 5678])
        XCTAssertEqual(series.reduce(0) { $0 + $1.tokens }, 6912)
        XCTAssertTrue(series.dropLast(2).allSatisfy { $0.tokens == 0 })
    }

    func testHistoryRendersCompactLightDarkAndZeroUsage() throws {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let days = ContributionHeatmap.dateColumns().flatMap { $0 }
        let daily = Dictionary(uniqueKeysWithValues: days.enumerated().map { index, date in
            (formatter.string(from: date), index % 11 == 0 ? 400_000_000 : (index % 7) * 9_000_000)
        })
        for (name, values, height, scheme) in [
            ("light", daily, CGFloat(171), ColorScheme.light),
            ("dark", daily, CGFloat(136), ColorScheme.dark),
            ("zero", [:], CGFloat(171), ColorScheme.light)
        ] {
            let content = TokenUsageHistoryView(daily: values)
                .frame(width: PopupLayout.columnWidth - 28, height: height)
                .padding(14)
                .background(scheme == .light ? Color.white : Color(white: 0.15))
                .environment(\.colorScheme, scheme)
                .environment(\.popupLiveUpdates, false)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage)
            XCTAssertEqual(image.size.height, height + 28, accuracy: 0.5)
            XCTAssertEqual(image.size.width, PopupLayout.columnWidth, accuracy: 0.5)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "/tmp/codexbar-history-\(name).png"))
        }
    }
}
