import AppKit
import Foundation
import UserNotifications

private struct Command: Decodable {
    let id: String
    let action: String
    let notificationID: String?
    let title: String?
    let body: String?
    let route: String?
}

private struct Reply: Encodable {
    let status: Int?
    let granted: Bool?
    let error: String?
}

private final class Notifier: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/codexbar/notification-bridge", isDirectory: true)
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        center.delegate = self
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.drain()
        }
        drain()
    }

    private func drain() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for url in urls where url.lastPathComponent.hasSuffix(".request.json") {
            guard let data = try? Data(contentsOf: url),
                  let command = try? JSONDecoder().decode(Command.self, from: data) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            try? FileManager.default.removeItem(at: url)
            handle(command)
        }
    }

    private func handle(_ command: Command) {
        switch command.action {
        case "status":
            center.getNotificationSettings { [weak self] settings in
                self?.reply(command, status: settings.authorizationStatus.rawValue)
            }
        case "authorize":
            center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
                self?.reply(command, granted: granted, error: error)
            }
        case "notify":
            guard let notificationID = command.notificationID,
                  let title = command.title,
                  let body = command.body else {
                reply(command, error: "Incomplete notification request")
                return
            }
            center.getNotificationSettings { [weak self] settings in
                guard let self else { return }
                if settings.authorizationStatus == .notDetermined {
                    self.center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                        if granted { self.schedule(command, id: notificationID, title: title, body: body) }
                        else { self.reply(command, error: error ?? NSError(domain: "CodexAppBarNotifier", code: 1, userInfo: [NSLocalizedDescriptionKey: "Notification permission was not granted"])) }
                    }
                } else if settings.authorizationStatus == .authorized
                            || settings.authorizationStatus == .provisional {
                    self.schedule(command, id: notificationID, title: title, body: body)
                } else {
                    self.reply(command, error: "Notification permission is disabled")
                }
            }
        case "quit":
            reply(command)
            DispatchQueue.main.async { NSApp.terminate(nil) }
        default:
            reply(command, error: "Unknown notification command")
        }
    }

    private func schedule(_ command: Command, id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["route": command.route ?? "app"]
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { [weak self] error in
            self?.reply(command, error: error)
        }
    }

    private func reply(_ command: Command, status: Int? = nil, granted: Bool? = nil, error: Error? = nil) {
        reply(command, status: status, granted: granted, error: error?.localizedDescription)
    }

    private func reply(_ command: Command, status: Int? = nil, granted: Bool? = nil, error: String?) {
        let response = Reply(status: status, granted: granted, error: error)
        guard let data = try? JSONEncoder().encode(response) else { return }
        let url = directory.appendingPathComponent("\(command.id).reply.json")
        try? data.write(to: url, options: .atomic)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let route = response.notification.request.content.userInfo["route"] as? String == "task" ? "task" : "app"
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        if let url = URL(string: "codexappbar://notification/\(route)") {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, _ in
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }
}

@main
private struct NotificationHelperApp {
    static func main() {
        let delegate = Notifier()
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
