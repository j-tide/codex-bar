import Foundation
import AppKit
import Combine
import CryptoKit

@MainActor
class OAuthManager: NSObject, ObservableObject {
    static let shared = OAuthManager()
    private let clientId = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let authURL = "https://auth.openai.com/oauth/authorize"
    private let tokenURL = "https://auth.openai.com/oauth/token"
    private let scope = "openid profile email offline_access api.connectors.read api.connectors.invoke"
    private let callbackPort: UInt16
    private let timeout: TimeInterval
    private let openURL: (URL) -> Bool
    @Published private(set) var isAuthorizing = false
    private var attemptID: UUID?
    private var codeVerifier = ""
    private var localServer: LocalCallbackServer?
    private var completionHandler: ((Result<OAuthTokens, Error>) -> Void)?
    private var timeoutWork: DispatchWorkItem?
    private var tokenTask: URLSessionDataTask?
    private var receivedCode = false
    private var redirectURI = ""

    init(callbackPort: UInt16 = 1455, timeout: TimeInterval = 180,
         openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.callbackPort = callbackPort
        self.timeout = timeout
        self.openURL = openURL
        super.init()
    }

    func startOAuth(completion: @escaping (Result<OAuthTokens, Error>) -> Void) {
        // A fresh user action replaces an abandoned browser flow immediately.
        cancelOAuth()
        let id = UUID()
        attemptID = id
        completionHandler = completion
        isAuthorizing = true
        receivedCode = false
        codeVerifier = generateCodeVerifier()
        let state = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let server = LocalCallbackServer(port: callbackPort)
        localServer = server
        do {
            try server.start(expectedState: state) { [weak self] code in
                guard let self, self.attemptID == id, !self.receivedCode else { return }
                self.receivedCode = true
                self.exchangeCode(code, id: id)
            }
        } catch {
            finish(.failure(error), id: id)
            return
        }
        redirectURI = "http://localhost:\(server.listeningPort)/auth/callback"
        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: generateCodeChallenge(from: codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: "Codex Desktop")
        ]
        guard let url = components.url else { finish(.failure(OAuthError.invalidURL), id: id); return }
        let expiration = DispatchWorkItem { [weak self] in
            self?.finish(.failure(OAuthError.timedOut), id: id)
        }
        timeoutWork = expiration
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: expiration)
        guard openURL(url) else { finish(.failure(OAuthError.browserUnavailable), id: id); return }
    }

    func cancelOAuth() {
        guard let id = attemptID else { return }
        finish(.failure(OAuthError.cancelled), id: id)
    }

    private func finish(_ result: Result<OAuthTokens, Error>, id: UUID) {
        guard attemptID == id else { return }
        attemptID = nil
        timeoutWork?.cancel()
        timeoutWork = nil
        tokenTask?.cancel()
        tokenTask = nil
        localServer?.stop()
        localServer = nil
        codeVerifier = ""
        isAuthorizing = false
        let completion = completionHandler
        completionHandler = nil
        completion?(result)
    }

    private func exchangeCode(_ code: String, id: UUID, attempt: Int = 0) {
        guard attemptID == id else { return }
        guard let url = URL(string: tokenURL) else { finish(.failure(OAuthError.invalidURL), id: id); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
        let body = ["grant_type": "authorization_code", "client_id": clientId, "code": code,
                    "redirect_uri": redirectURI, "code_verifier": codeVerifier]
        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        tokenTask = session.dataTask(with: request) { [weak self] data, _, error in
            session.finishTasksAndInvalidate()
            DispatchQueue.main.async {
                guard let self, self.attemptID == id else { return }
                if let error {
                    let nsError = error as NSError
                    let transient = [NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut, NSURLErrorCannotConnectToHost]
                    if attempt < 2, nsError.domain == NSURLErrorDomain, transient.contains(nsError.code) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.6 : 1.5)) { [weak self] in
                            self?.exchangeCode(code, id: id, attempt: attempt + 1)
                        }
                    } else { self.finish(.failure(error), id: id) }
                    return
                }
                guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.finish(.failure(OAuthError.noToken), id: id); return
                }
                if let message = json["error"] as? String {
                    self.finish(.failure(OAuthError.serverError(message)), id: id); return
                }
                guard let access = json["access_token"] as? String,
                      let refresh = json["refresh_token"] as? String,
                      let identity = json["id_token"] as? String else {
                    self.finish(.failure(OAuthError.noToken), id: id); return
                }
                self.finish(.success(OAuthTokens(accessToken: access, refreshToken: refresh, idToken: identity)), id: id)
            }
        }
        tokenTask?.resume()
    }

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = verifier.data(using: .ascii)!
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct OAuthTokens {
    let accessToken: String
    let refreshToken: String
    let idToken: String
}

enum OAuthError: LocalizedError {
    case invalidURL, noToken, cancelled, timedOut, browserUnavailable, callbackUnavailable
    case serverError(String)
    var errorDescription: String? {
        switch self {
        case .invalidURL: return L.zh ? "无效的授权地址" : "Invalid authorization URL"
        case .noToken: return L.zh ? "未获取到授权凭据，请重试" : "No credentials received. Please retry."
        case .cancelled: return L.zh ? "已取消授权" : "Authorization cancelled"
        case .timedOut: return L.zh ? "授权等待已超时，请重新添加账号" : "Authorization timed out. Add the account again."
        case .browserUnavailable: return L.zh ? "无法打开授权网页，请重试" : "Could not open the authorization page. Please retry."
        case .callbackUnavailable: return L.zh ? "授权回调端口不可用，请结束其他登录流程后重试" : "Authorization callback port unavailable. Finish other sign-in flows and retry."
        case .serverError(let message): return L.zh ? "授权失败: \(message)" : "Authorization failed: \(message)"
        }
    }
}

/// Nonblocking, main-queue socket ownership: stop releases the port synchronously.
@MainActor
final class LocalCallbackServer {
    private let port: UInt16
    private(set) var listeningPort: UInt16 = 0
    private var acceptTimer: Timer?
    private var listenerFD: Int32 = -1
    private struct Client {
        let source: DispatchSourceRead
        let expiration: DispatchWorkItem
        var bytes = Data()
    }
    private var clients: [Int32: Client] = [:]
    private var expectedState = ""
    private var handler: ((String) -> Void)?

    init(port: UInt16) { self.port = port }

    func start(expectedState: String, handler: @escaping (String) -> Void) throws {
        stop()
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw OAuthError.callbackUnavailable }
        var ready = false
        defer { if !ready { close(fd) } }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, Darwin.listen(fd, 5) == 0,
              fcntl(fd, F_SETFL, O_NONBLOCK) != -1 else { throw OAuthError.callbackUnavailable }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(fd, $0, &length) }
        }
        listeningPort = UInt16(bigEndian: address.sin_port)
        self.expectedState = expectedState
        self.handler = handler
        listenerFD = fd
        // A nonblocking accept check exists only during browser authorization.
        // Owning the listening descriptor directly lets cancel/restart release
        // it synchronously, without waiting for a Dispatch source cancellation.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.acceptClients()
        }
        acceptTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        ready = true
    }

    func stop() {
        acceptTimer?.invalidate()
        acceptTimer = nil
        if listenerFD >= 0 { close(listenerFD); listenerFD = -1 }
        for fd in Array(clients.keys) { closeClient(fd) }
        handler = nil
    }

    private func acceptClients() {
        guard listenerFD >= 0 else { return }
        for _ in 0..<16 {
            let fd = accept(listenerFD, nil, nil)
            guard fd >= 0 else { return }
            guard fcntl(fd, F_SETFL, O_NONBLOCK) != -1 else { close(fd); continue }
            var noSignal: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            let expiration = DispatchWorkItem { [weak self] in self?.closeClient(fd) }
            clients[fd] = Client(source: source, expiration: expiration)
            source.setEventHandler { [weak self] in self?.readClient(fd) }
            source.setCancelHandler { close(fd) }
            source.resume()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: expiration)
        }
    }

    private func closeClient(_ fd: Int32) {
        guard let client = clients.removeValue(forKey: fd) else { return }
        client.expiration.cancel()
        client.source.cancel()
        shutdown(fd, SHUT_RDWR)
    }

    private func readClient(_ fd: Int32) {
        guard clients[fd] != nil else { return }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = recv(fd, &buffer, buffer.count, 0)
        guard count > 0 else {
            if count == 0 || (errno != EAGAIN && errno != EWOULDBLOCK) { closeClient(fd) }
            return
        }
        clients[fd]?.bytes.append(contentsOf: buffer.prefix(count))
        guard let bytes = clients[fd]?.bytes else { return }
        guard bytes.count <= 16384 else { closeClient(fd); return }
        guard let request = String(data: bytes, encoding: .utf8), request.contains("\r\n\r\n") else { return }
        let path = request.components(separatedBy: "\r\n")[0].components(separatedBy: " ")
        guard path.count >= 2, path[0] == "GET",
              let url = URLComponents(string: "http://localhost" + path[1]), url.path == "/auth/callback",
              url.queryItems?.first(where: { $0.name == "state" })?.value == expectedState,
              let code = url.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            respond(fd, status: "400 Bad Request", body: "This authorization link is no longer valid. Return to CodexAppBar and use the latest page.")
            return
        }
        let html = OAuthCallbackPage.html(chinese: L.zh)
        respond(fd, status: "200 OK", body: html)
        // Only the expected state consumes the one-shot callback. Stale browser
        // pages cannot stop the current listener or fail a replacement flow.
        let completion = handler
        stop()
        completion?(code)
    }

    private func respond(_ fd: Int32, status: String, body: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        _ = response.withCString { send(fd, $0, strlen($0), 0) }
        closeClient(fd)
    }
}
