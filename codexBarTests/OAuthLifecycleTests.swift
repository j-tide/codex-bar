import XCTest
@testable import codexAppBar

@MainActor
final class OAuthLifecycleTests: XCTestCase {
    private func callback(_ authorization: URL) throws -> URLComponents {
        let items = try XCTUnwrap(URLComponents(url: authorization, resolvingAgainstBaseURL: false)?.queryItems)
        let redirect = try XCTUnwrap(items.first { $0.name == "redirect_uri" }?.value)
        return try XCTUnwrap(URLComponents(string: redirect))
    }

    func testAbandonedAttemptCanRestartAndCancelWithoutOpeningBrowser() throws {
        var urls: [URL] = []
        var cancellations = 0
        let manager = OAuthManager(callbackPort: 0, openURL: { urls.append($0); return true })
        defer { manager.cancelOAuth() }
        manager.startOAuth { result in
            if case .failure(OAuthError.cancelled) = result { cancellations += 1 }
            else { XCTFail("Expected cancellation") }
        }
        XCTAssertTrue(manager.isAuthorizing)
        manager.startOAuth { result in
            if case .failure(OAuthError.cancelled) = result { cancellations += 1 }
            else { XCTFail("Expected cancellation") }
        }
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(urls.count, 2)
        let states = urls.map { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value }
        XCTAssertNotEqual(states[0], states[1])
        manager.cancelOAuth()
        XCTAssertFalse(manager.isAuthorizing)
        XCTAssertEqual(cancellations, 2)
    }

    func testClosedAttemptReleasesPortImmediately() throws {
        var url: URL?
        let manager = OAuthManager(callbackPort: 0, openURL: { url = $0; return true })
        manager.startOAuth { _ in }
        let port = try XCTUnwrap(try callback(XCTUnwrap(url)).port)
        manager.cancelOAuth()
        let server = LocalCallbackServer(port: UInt16(port))
        defer { server.stop() }
        XCTAssertNoThrow(try server.start(expectedState: "new") { _ in })
    }

    func testBrowserOpenFailureDoesNotLeavePendingAttempt() {
        var failures = 0
        let manager = OAuthManager(callbackPort: 0, openURL: { _ in false })
        manager.startOAuth { result in
            if case .failure(OAuthError.browserUnavailable) = result { failures += 1 }
        }
        XCTAssertFalse(manager.isAuthorizing)
        manager.startOAuth { result in
            if case .failure(OAuthError.browserUnavailable) = result { failures += 1 }
        }
        XCTAssertFalse(manager.isAuthorizing)
        XCTAssertEqual(failures, 2)
    }

    func testBusyPortReportsFailureBeforeOpeningBrowser() throws {
        let server = LocalCallbackServer(port: 0)
        try server.start(expectedState: "owner") { _ in }
        defer { server.stop() }
        var browserOpened = false
        let manager = OAuthManager(callbackPort: server.listeningPort, openURL: { _ in browserOpened = true; return true })
        var correctFailure = false
        manager.startOAuth { result in
            if case .failure(OAuthError.callbackUnavailable) = result { correctFailure = true }
        }
        XCTAssertTrue(correctFailure)
        XCTAssertFalse(browserOpened)
        XCTAssertFalse(manager.isAuthorizing)
    }

    func testTimeoutReleasesPendingAttempt() async throws {
        let expired = expectation(description: "expires")
        let manager = OAuthManager(callbackPort: 0, timeout: 0.05, openURL: { _ in true })
        manager.startOAuth { result in
            if case .failure(OAuthError.timedOut) = result { expired.fulfill() }
            else { XCTFail("Expected timeout") }
        }
        await fulfillment(of: [expired], timeout: 2)
        XCTAssertFalse(manager.isAuthorizing)
    }

    func testCancelledTimeoutCannotExpireReplacement() async throws {
        let manager = OAuthManager(callbackPort: 0, timeout: 0.3, openURL: { _ in true })
        defer { manager.cancelOAuth() }
        manager.startOAuth { _ in }
        try await Task.sleep(for: .milliseconds(200))
        manager.startOAuth { result in
            if case .failure(OAuthError.cancelled) = result { return }
            XCTFail("The replacement should still be waiting")
        }
        try await Task.sleep(for: .milliseconds(170))
        XCTAssertTrue(manager.isAuthorizing)
    }

    func testStaleStateAndWrongPathDoNotConsumeCurrentCallback() async throws {
        let server = LocalCallbackServer(port: 0)
        var received: [String] = []
        try server.start(expectedState: "current") { received.append($0) }
        defer { server.stop() }
        let port = server.listeningPort
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        for path in ["/auth/callback?code=old&state=stale", "/wrong?code=old&state=current", "/auth/callback?code=&state=current"] {
            let (_, response) = try await session.data(from: XCTUnwrap(URL(string: "http://127.0.0.1:\(port)\(path)")))
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 400)
            XCTAssertTrue(received.isEmpty)
        }
        let (data, response) = try await session.data(from: XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/auth/callback?code=valid&state=current")))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(String(data: data, encoding: .utf8), OAuthCallbackPage.html(chinese: L.zh))
        XCTAssertEqual(received, ["valid"])
        let replacement = LocalCallbackServer(port: port)
        defer { replacement.stop() }
        XCTAssertNoThrow(try replacement.start(expectedState: "next") { _ in })
    }
    func testReturnRouteOnlyAcceptsPanelOpenWithoutPayload() {
        XCTAssertTrue(OAuthCallbackPage.isReturnURL(URL(string: OAuthCallbackPage.returnURL)!))
        for value in ["codexappbar://delete", "codexappbar://open?code=secret",
                      "https://open", "codexappbar://open/other", "codexappbar://user@open"] {
            XCTAssertFalse(OAuthCallbackPage.isReturnURL(URL(string: value)!))
        }
    }

    func testCallbackPageSeparatesLanguagesAndDoesNotClaimTokenSuccess() {
        let chinese = OAuthCallbackPage.html(chinese: true)
        let english = OAuthCallbackPage.html(chinese: false)
        XCTAssertTrue(chinese.contains("授权已接收"))
        XCTAssertFalse(chinese.contains("Authorization received"))
        XCTAssertTrue(english.contains("Authorization received"))
        XCTAssertFalse(english.contains("授权已接收"))
        XCTAssertTrue(english.contains("finishing account verification"))
        XCTAssertTrue(chinese.contains("href=\"codexappbar://open\""))
    }

}
