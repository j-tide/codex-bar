import XCTest
@testable import codexAppBar

@MainActor
final class AppUpdateAssetTests: XCTestCase {
    private let zipHash = "sha256:" + String(repeating: "a", count: 64)
    private let dmgHash = "sha256:" + String(repeating: "b", count: 64)

    private func row(_ suffix: String, digest: String?) -> String {
        """
        <li data-view-component="true" class="Box-row">
          <div><a href="/iamzjt-front-end/codexbar/releases/download/v2026.09.14/codexAppBar-v2026.09.14-release.\(suffix)"><span>Download</span></a></div>
          <div><span>\(digest ?? "")</span></div>
        </li>
        """
    }

    func testZIPDigestBelongsToZIPRegardlessOfAssetOrder() throws {
        let zip = row("zip", digest: zipHash)
        let dmg = row("dmg", digest: dmgHash)
        for html in [dmg + zip, zip + dmg] {
            let asset = try AppUpdateService.installableWebAsset(in: "<ul>\(html)</ul>")
            XCTAssertEqual(asset.url.absoluteString,
                "https://github.com/iamzjt-front-end/codexbar/releases/download/v2026.09.14/codexAppBar-v2026.09.14-release.zip")
            XCTAssertEqual(asset.digest, zipHash)
        }
    }

    func testMissingZIPDigestNeverBorrowsAdjacentAssetDigest() throws {
        let zip = row("zip", digest: nil)
        let dmg = row("dmg", digest: dmgHash)
        for html in [dmg + zip, zip + dmg] {
            XCTAssertNil(try AppUpdateService.installableWebAsset(in: html).digest)
        }
    }

    func testSingleZIPStillWorksAndNoZIPIsRejected() throws {
        XCTAssertEqual(try AppUpdateService.installableWebAsset(in: row("zip", digest: zipHash)).digest, zipHash)
        XCTAssertThrowsError(try AppUpdateService.installableWebAsset(in: row("dmg", digest: dmgHash)))
        XCTAssertThrowsError(try AppUpdateService.installableWebAsset(in: "<html>invalid response</html>"))
    }

    func testCompletedUpdatePromptOnlyMatchesInstalledBuild() {
        XCTAssertEqual(
            AppUpdateService.pendingInstallState(build: "20260914.2", tagName: "v2026.09.14.2"),
            .completed
        )
        XCTAssertEqual(
            AppUpdateService.pendingInstallState(build: "20260914.1", tagName: "v2026.09.14.2"),
            .waiting
        )
        XCTAssertEqual(
            AppUpdateService.pendingInstallState(build: "20260914.2", tagName: "v2026.09.14.1"),
            .stale
        )
    }
}
