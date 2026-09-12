import AppKit
import SwiftUI
import XCTest
@testable import codexAppBar

@MainActor
final class MenuBarGlassPanelTests: XCTestCase {
    func testVisiblePanelCloseRemovesContentAfterTransition() async throws {
        let panel = MenuBarGlassPanel()
        panel.contentViewController = NSHostingController(rootView: Text("Transition").frame(width: 100, height: 60))
        panel.setFrame(NSRect(x: 100, y: 100, width: 100, height: 60), display: false)
        panel.orderFront(nil)
        panel.close()
        panel.close()
        XCTAssertFalse(panel.isShown, "Toggle must see the closing panel as closed immediately")
        try await Task.sleep(for: .milliseconds(220))
        XCTAssertFalse(panel.isVisible)
        XCTAssertNil(panel.contentViewController)
    }

    func testStatusButtonMouseDownDoesNotCloseBeforeMouseUpToggle() {
        let anchorWindow = NSWindow(contentRect: NSRect(x: 200, y: 500, width: 200, height: 24),
                                    styleMask: .borderless, backing: .buffered, defer: false)
        anchorWindow.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSRect(x: 20, y: 0, width: 160, height: 24))
        anchorWindow.contentView?.addSubview(anchor)
        let panel = MenuBarGlassPanel()
        panel.contentViewController = NSHostingController(rootView: Text("Preview").frame(width: 200, height: 100))
        panel.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        defer { panel.close(); anchorWindow.close() }
        XCTAssertFalse(panel.shouldDismissForClick(at: NSPoint(x: 300, y: 512)),
                       "Anchor clicks must reach the toggle without first dismissing the panel")
        XCTAssertTrue(panel.isShown)
        panel.performClose(nil)
        XCTAssertFalse(panel.isShown)
    }

    func testModalDialogKeepsPopupAliveAndRestoresItsLevel() {
        let panel = MenuBarGlassPanel()
        panel.contentViewController = NSHostingController(rootView: Text("Preview"))
        panel.orderFront(nil)
        defer { panel.close() }
        let outside = NSPoint(x: -10000, y: -10000)
        XCTAssertTrue(panel.shouldDismissForClick(at: outside))
        PopupModalPresenter.run {
            XCTAssertEqual(panel.level, .normal)
            XCTAssertFalse(panel.shouldDismissForClick(at: outside))
            PopupModalPresenter.run { XCTAssertTrue(PopupModalPresenter.isPresenting) }
            XCTAssertTrue(PopupModalPresenter.isPresenting)
        }
        XCTAssertFalse(PopupModalPresenter.isPresenting)
        XCTAssertEqual(panel.level, .popUpMenu)
        XCTAssertTrue(panel.isShown)
        XCTAssertNotNil(panel.contentViewController)
    }

    func testQuitCancellationAndConfirmationDispatch() {
        var terminations = 0
        AppQuitConfirmation.request(confirm: { false }, terminate: { terminations += 1 })
        XCTAssertEqual(terminations, 0, "Cancel must leave the process running")
        AppQuitConfirmation.request(confirm: { true }, terminate: { terminations += 1 })
        XCTAssertEqual(terminations, 1, "Confirm must terminate, not just close the panel")
        AppQuitConfirmation.request(confirm: {
            AppQuitConfirmation.request(confirm: { true }, terminate: { terminations += 1 })
            return false
        }, terminate: { terminations += 1 })
        XCTAssertEqual(terminations, 1, "Repeated requests during confirmation must be ignored")
    }

    func testHostingSizeNotificationsCoalesceAndIgnoreUnchangedGeometry() async throws {
        let host = FirstMouseHostingView(rootView: Text("Sizing").frame(width: 100, height: 40))
        host.sizingOptions = [.minSize, .intrinsicContentSize]
        var notifications = 0
        host.onSizeChange = { notifications += 1 }
        for _ in 0..<20 { host.invalidateIntrinsicContentSize() }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(notifications, 1)
        for _ in 0..<20 { host.invalidateIntrinsicContentSize() }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(notifications, 1, "Animation invalidations must not resize an unchanged panel")
        host.rootView = Text("Sizing").frame(width: 100, height: 80)
        host.invalidateIntrinsicContentSize()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(notifications, 2, "Real content height changes must still reach the window")
    }

    func testArrowAndBodyAreOneContinuousOutline() {
        let bounds = CGRect(x: 0, y: 0, width: 736, height: 600)
        let outline = PopupGlassOutline(arrowX: 368).path(in: bounds)
        XCTAssertTrue(outline.contains(CGPoint(x: 368, y: 6)))
        XCTAssertTrue(outline.contains(CGPoint(x: 368, y: 14)))
        XCTAssertTrue(outline.contains(CGPoint(x: 100, y: 40)))
        XCTAssertFalse(outline.contains(CGPoint(x: 100, y: 6)))
        XCTAssertFalse(outline.contains(CGPoint(x: 0, y: 599)))
        XCTAssertEqual(outline.boundingRect.maxY, bounds.maxY)
    }

    func testPanelClampsAtEitherScreenEdgeAndPreservesMenuAnchor() {
        let screen = NSRect(x: 100, y: 0, width: 1440, height: 876)
        let size = NSSize(width: 736, height: 600)
        for x in [CGFloat(160), 800, 1450] {
            let anchor = NSRect(x: x, y: 876, width: 30, height: 24)
            let frame = MenuBarPopoverPlacement.frame(size: size, anchor: anchor, screen: screen)
            XCTAssertGreaterThanOrEqual(frame.minX, screen.minX + 8)
            XCTAssertLessThanOrEqual(frame.maxX, screen.maxX - 8)
            XCTAssertEqual(frame.maxY, anchor.minY)
            XCTAssertFalse(frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)), "Transparent shadow must not cover the menu item")
            let arrowX = anchor.midX - frame.minX
            XCTAssertTrue(PopupGlassOutline(arrowX: arrowX).path(in: NSRect(origin: .zero, size: size))
                .contains(CGPoint(x: arrowX, y: 8)))
        }
    }

    func testGlassHostReceivesBlankAndDisabledAreasWithoutCapturingShadow() {
        let panel = MenuBarGlassPanel()
        panel.placement.arrowX = 174
        let root = VStack {
            Button("Disabled refresh") {}.disabled(true)
            Spacer()
        }.frame(width: 300, height: 200).padding(.horizontal, 24).padding(.bottom, 24)
        let host = FirstMouseHostingView(rootView: root)
        panel.contentView = host
        panel.setContentSize(NSSize(width: 348, height: 224))
        host.layoutSubtreeIfNeeded()
        defer { panel.close() }
        XCTAssertFalse(panel.ignoresMouseEvents)
        func hit(_ topDown: NSPoint) -> NSView? {
            let local = NSPoint(x: topDown.x, y: host.isFlipped ? topDown.y : host.bounds.height - topDown.y)
            return host.hitTest(host.convert(local, to: host.superview))
        }
        for point in [NSPoint(x: 174, y: 30), NSPoint(x: 174, y: 50),
                      NSPoint(x: 40, y: 100), NSPoint(x: 174, y: 180)] {
            XCTAssertNotNil(hit(point), "Visible glass must receive clicks at \(point)")
        }
        for point in [NSPoint(x: 0, y: 100), NSPoint(x: 174, y: 0),
                      NSPoint(x: 25, y: 223), NSPoint(x: 25, y: 13)] {
            XCTAssertNil(hit(point), "Shadow and rounded/arrow cutouts must stay outside at \(point)")
        }

    }

    func testCloseReleasesHostedContentAndCanBeRepeated() {
        let panel = MenuBarGlassPanel()
        panel.contentViewController = NSHostingController(rootView: Text("Preview"))
        panel.close()
        panel.close()
        XCTAssertNil(panel.contentViewController)
        XCTAssertFalse(panel.isShown)
    }
}
