import SwiftUI
import XCTest
@testable import codexAppBar

@MainActor
final class AccountPlanBadgeTests: XCTestCase {
    func testProTierBadgesUseTheirOwnNamesAndColors() {
        let cases: [(planType: String, title: String, tone: AccountPlanBadge.Tone)] = [
            ("prolite", "PRO 5X", .proFive),
            ("PRO_5X", "PRO 5X", .proFive),
            ("codex-pro-5x", "PRO 5X", .proFive),
            ("pro10x", "PRO 10X", .proTen),
            ("codex_pro_10x", "PRO 10X", .proTen),
            ("PRO 25X", "PRO 25X", .proTwentyFive),
            ("codexpro25x", "PRO 25X", .proTwentyFive)
        ]

        for entry in cases {
            let badge = AccountPlanBadge(planType: entry.planType)
            XCTAssertEqual(badge.title, entry.title, entry.planType)
            XCTAssertEqual(badge.tone, entry.tone, entry.planType)
        }

        let colors = ["pro5x", "pro10x", "pro25x"].map { planType in
            let resolved = AccountPlanBadge(planType: planType).tone.color.resolve(in: EnvironmentValues())
            return [resolved.red, resolved.green, resolved.blue]
        }
        XCTAssertEqual(Set(colors).count, 3, "Each Pro tier needs a distinct visible tint")
    }

    func testLegacyProNamesDoNotClaimAnObsoleteTier() {
        for planType in ["pro", "promax", "pro20x", "codexpro20x"] {
            let badge = AccountPlanBadge(planType: planType)
            XCTAssertEqual(badge.title, "PRO", planType)
        }
        XCTAssertEqual(AccountPlanBadge(planType: "plus").title, "PLUS")
    }
}
