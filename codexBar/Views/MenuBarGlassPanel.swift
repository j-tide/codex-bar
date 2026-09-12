import AppKit
import SwiftUI
import Combine
import QuartzCore
import OSLog

@MainActor
final class MenuBarPopoverPlacement: ObservableObject {
    static let shadowInset: CGFloat = 24
    @Published var arrowX: CGFloat = PopupLayout.width / 2 + shadowInset

    static func frame(size: NSSize, anchor: NSRect, screen: NSRect) -> NSRect {
        let x = min(max(anchor.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        return NSRect(x: x, y: max(screen.minY + 4, anchor.minY - size.height), width: size.width, height: size.height)
    }
}

struct MenuBarPopoverRoot<Content: View>: View {
    @ObservedObject var placement: MenuBarPopoverPlacement
    let content: Content
    var body: some View {
        content.environment(\.popupArrowX, placement.arrowX - MenuBarPopoverPlacement.shadowInset)
            .padding(.horizontal, MenuBarPopoverPlacement.shadowInset)
            .padding(.bottom, MenuBarPopoverPlacement.shadowInset)
    }
}

/// A transparent host lets SwiftUI draw one glass outline, including the arrow.
@MainActor
final class MenuBarGlassPanel: NSPanel {
    let placement = MenuBarPopoverPlacement()
    private weak var anchorView: NSView?
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var closing = false
    private var closeTask: Task<Void, Never>?
    var isShown: Bool { isVisible && !closing }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        ignoresMouseEvents = false
        backgroundColor = .clear
        // Glass supplies the contour; AppKit's rectangular host shadow leaves a
        // second outline around transparent corners and the arrow.
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .popUpMenu
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        animationBehavior = .none
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Same top-down outline used by SwiftUI, excluding the transparent shadow.
    func contentHitPath(in size: NSSize) -> Path {
        let inset = MenuBarPopoverPlacement.shadowInset
        // No transparent top margin: the NSPanel must never cover its status
        // button. A nil view hit-test cannot forward a click through an NSWindow.
        let body = NSRect(x: inset, y: 0, width: size.width - 2 * inset, height: size.height - inset)
        return PopupGlassOutline(arrowX: placement.arrowX - inset).path(in: body)
    }

    func setAppearance(_ name: String) {
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let view = contentView {
            view.wantsLayer = true
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.4
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            view.layer?.add(transition, forKey: "popupAppearance")
        }
        appearance = name == "dark" ? NSAppearance(named: .darkAqua)
            : name == "light" ? NSAppearance(named: .aqua) : nil
    }

    func show(relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge) {
        closeTask?.cancel()
        closeTask = nil
        closing = false
        anchorView = view
        resizeToFitContent()
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        alphaValue = animate ? 0 : 1
        makeKeyAndOrderFront(nil)
        if animate {
            animateContent(from: -5, to: 0, duration: 0.20)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
            }
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.shouldDismissForClick(at: NSEvent.mouseLocation) else { return }
            Logger(subsystem: "xmasdong.codexAppBar", category: "PopupLifecycle").debug("Dismiss: outside click")
            self.close()
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, event.window === self { self?.close(); return nil }
            return event
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            Logger(subsystem: "xmasdong.codexAppBar", category: "PopupLifecycle").debug("Dismiss: activated \(app.bundleIdentifier ?? "unknown", privacy: .public)")
            MainActor.assumeIsolated {
                if !PopupModalPresenter.isPresenting { self?.close() }
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.resizeToFitContent() } }
    }

    /// Let the status button handle its own mouse-up. Closing on mouse-down
    /// would make that same click reopen the panel in the button's toggle action.
    func shouldDismissForClick(at screenPoint: NSPoint) -> Bool {
        if PopupModalPresenter.isPresenting || NSApp.modalWindow != nil { return false }
        if frame.contains(screenPoint) { return false }
        if let anchorView, let window = anchorView.window {
            let anchor = window.convertToScreen(anchorView.convert(anchorView.bounds, to: nil))
            if anchor.contains(screenPoint) { return false }
        }
        return true
    }

    func resizeToFitContent() {
        guard let anchorView, let anchorWindow = anchorView.window, let contentView else { return }
        let anchor = anchorWindow.convertToScreen(anchorView.convert(anchorView.bounds, to: nil))
        let size = contentView.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        let screen = anchorWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchor
        let target = MenuBarPopoverPlacement.frame(size: size, anchor: anchor, screen: screen)
        if frame != target { setFrame(target, display: true) }
        let arrowX = anchor.midX - target.minX
        if placement.arrowX != arrowX { placement.arrowX = arrowX }
    }

    override func performClose(_ sender: Any?) { close() }
    override func cancelOperation(_ sender: Any?) { close() }
    override func close() {
        guard !closing else { return }
        closing = true
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        outsideClickMonitor = nil
        keyMonitor = nil
        activationObserver = nil
        screenObserver = nil
        guard isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            finishClosing()
            return
        }
        animateContent(from: 0, to: -4, duration: 0.14)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }
        closeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            finishClosing()
        }
    }

    private func animateContent(from: CGFloat, to: CGFloat, duration: TimeInterval) {
        contentView?.wantsLayer = true
        let motion = CABasicAnimation(keyPath: "transform.translation.y")
        motion.fromValue = from
        motion.toValue = to
        motion.duration = duration
        motion.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        motion.fillMode = .forwards
        motion.isRemovedOnCompletion = false
        contentView?.layer?.add(motion, forKey: "popupVisibility")
    }

    private func finishClosing() {
        super.close()
        contentView?.layer?.removeAnimation(forKey: "popupVisibility")
        contentViewController = nil
        alphaValue = 1
        closeTask = nil
        closing = false
    }
}
