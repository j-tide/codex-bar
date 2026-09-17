import AppKit

/// Keep native dialogs above the floating popup, without destroying its view state.
@MainActor
enum PopupModalPresenter {
    private(set) static var isPresenting = false

    @discardableResult
    static func run<T>(_ operation: () -> T) -> T {
        let wasPresenting = isPresenting
        isPresenting = true
        let panels = NSApp.windows.compactMap { $0 as? MenuBarGlassPanel }.filter(\.isVisible)
        let levels = panels.map(\.level)
        panels.forEach { $0.level = .normal }
        NSApp.activate(ignoringOtherApps: true)
        defer {
            for (panel, level) in zip(panels, levels) { panel.level = level }
            panels.first(where: \.isVisible)?.makeKeyAndOrderFront(nil)
            isPresenting = wasPresenting
        }
        return operation()
    }
}

@MainActor
enum AppQuitConfirmation {
    private static var isRequesting = false

    static func request(
        confirm: (() -> Bool)? = nil,
        terminate: (() -> Void)? = nil
    ) {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        guard (confirm ?? showConfirmation)() else { return }
        if let terminate { terminate() }
        else { NSApp.terminate(nil) }
    }

    private static func showConfirmation() -> Bool {
        let alert = NSAlert()
        alert.messageText = L.zh ? "退出 codex-bar？" : "Quit codex-bar?"
        alert.informativeText = L.zh
            ? "退出后将停止额度刷新和任务提醒。Codex 中正在运行的任务不受影响。"
            : "Quota refreshes and task notifications will stop. Running tasks in Codex will continue."
        alert.addButton(withTitle: L.cancel)
        alert.addButton(withTitle: L.quit)
        return PopupModalPresenter.run { alert.runModal() } == .alertSecondButtonReturn
    }
}
