import AppKit
import Foundation
import UserNotifications

/// A separately identified app owns notifications so macOS uses the current icon.
/// Requests and acknowledgements are private files because both apps are unsandboxed.
final class NotificationBridge {
    static let shared = NotificationBridge()

    private struct Command: Encodable {
        let id: String
        let action: String
        let notificationID: String?
        let title: String?
        let body: String?
        let route: String?
    }

    private struct Reply: Decodable {
        let status: Int?
        let granted: Bool?
        let error: String?
    }

    private let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/codexbar/notification-bridge", isDirectory: true)
    private let helperID = "xmasdong.codexAppBar.notifications"

    private init() {}

    func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        send(action: "status") { result in
            let raw = try? result.get().status
            completion(raw.flatMap(UNAuthorizationStatus.init(rawValue:)) ?? .notDetermined)
        }
    }

    func requestAuthorization(completion: @escaping (Result<Bool, Error>) -> Void) {
        send(action: "authorize", timeout: 120) { result in
            completion(result.map { $0.granted == true })
        }
    }

    func add(_ request: UNNotificationRequest, route: String, completion: @escaping (Error?) -> Void) {
        send(
            action: "notify", notificationID: request.identifier,
            title: request.content.title, body: request.content.body, route: route,
            timeout: 120
        ) { result in
            switch result {
            case .success: completion(nil)
            case .failure(let error): completion(error)
            }
        }
    }

    func stop() {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: helperID).isEmpty else { return }
        send(action: "quit", timeout: 2) { _ in }
    }

    private func send(
        action: String,
        notificationID: String? = nil,
        title: String? = nil,
        body: String? = nil,
        route: String? = nil,
        timeout: TimeInterval = 10,
        completion: @escaping (Result<Reply, Error>) -> Void
    ) {
        let id = UUID().uuidString
        let command = Command(id: id, action: action, notificationID: notificationID,
                              title: title, body: body, route: route)
        let requestURL = directory.appendingPathComponent("\(id).request.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let data = try JSONEncoder().encode(command)
            try data.write(to: requestURL, options: .atomic)
        } catch {
            completion(.failure(error))
            return
        }

        let helperURL = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/Helpers/CodexAppBarNotifier.app", isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: helperURL.path) else {
            try? FileManager.default.removeItem(at: requestURL)
            completion(.failure(NSError(domain: "CodexAppBarNotifier", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Notification helper is missing"])))
            return
        }
        let waitForReply = { [directory] in
            DispatchQueue.global(qos: .utility).async {
                let replyURL = directory.appendingPathComponent("\(id).reply.json")
                let deadline = Date().addingTimeInterval(timeout)
                while Date() < deadline {
                    if let data = try? Data(contentsOf: replyURL),
                       let reply = try? JSONDecoder().decode(Reply.self, from: data) {
                        try? FileManager.default.removeItem(at: replyURL)
                        if let error = reply.error {
                            completion(.failure(NSError(domain: "CodexAppBarNotifier", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: error])))
                        } else {
                            completion(.success(reply))
                        }
                        return
                    }
                    Thread.sleep(forTimeInterval: 0.1)
                }
                try? FileManager.default.removeItem(at: requestURL)
                completion(.failure(NSError(domain: "CodexAppBarNotifier", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Notification helper did not respond"])))
            }
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: helperID).isEmpty {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration) { _, error in
                if let error {
                    try? FileManager.default.removeItem(at: requestURL)
                    completion(.failure(error))
                }
                else { waitForReply() }
            }
        } else {
            waitForReply()
        }
    }
}
