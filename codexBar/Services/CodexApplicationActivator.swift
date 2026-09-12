import AppKit

@MainActor
enum CodexApplicationActivator {
    static func taskURL(for threadID: String?) -> URL? {
        guard let threadID, UUID(uuidString: threadID) != nil else { return nil }
        return URL(string: "codex://threads/\(threadID)")
    }

    @discardableResult
    static func openTask(_ threadID: String?) -> Bool {
        if let url = taskURL(for: threadID), NSWorkspace.shared.open(url) { return true }
        activate()
        return false
    }

    static func activate() {
        let workspace = NSWorkspace.shared
        if let app = workspace.runningApplications.first(where: {
            $0.bundleIdentifier == "com.openai.codex"
        }) {
            _ = app.activate(options: [.activateAllWindows])
            return
        }

        guard let appURL = workspace.urlForApplication(withBundleIdentifier: "com.openai.codex") else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: appURL, configuration: configuration) { _, _ in }
    }
}
