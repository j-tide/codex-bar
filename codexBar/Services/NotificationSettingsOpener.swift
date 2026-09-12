import AppKit
import OSLog

/// Keep the launch alive independently of the menu view that initiated it.
@MainActor
final class NotificationSettingsOpener {
    static let shared = NotificationSettingsOpener()
    private var isOpening = false

    func open(completion: @escaping (Bool) -> Void) {
        guard !isOpening else { return }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences"),
              let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            completion(false)
            return
        }
        isOpening = true
        // Finish dismissing both menu windows before another application gains focus.
        DispatchQueue.main.async { [self] in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([settingsURL], withApplicationAt: appURL, configuration: configuration) { app, error in
                Task { @MainActor in
                    guard let app, error == nil else {
                        self.openRoot(appURL, completion: completion)
                        return
                    }
                    app.activate(options: [.activateAllWindows])
                    // LaunchServices accepting a URL does not prove that Settings stayed open.
                    try? await Task.sleep(for: .seconds(2))
                    if app.isTerminated {
                        self.openRoot(appURL, completion: completion)
                    } else {
                        self.isOpening = false
                        Logger(subsystem: Bundle.main.bundleIdentifier ?? "codexbar", category: "TaskNotifications")
                            .notice("Notification Settings launch verified, pid=\(app.processIdentifier)")
                        completion(true)
                    }
                }
            }
        }
    }

    private func openRoot(_ appURL: URL, completion: @escaping (Bool) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
            Task { @MainActor in
                self.isOpening = false
                if let app, error == nil {
                    app.activate(options: [.activateAllWindows])
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }
    }
}
