import AppKit
import SwiftUI
import NookCore
import os

/// Status buttons are remotely hosted on current macOS. Place the shelf in
/// screen coordinates instead of letting NSPopover convert that remote view.
@MainActor final class ShelfController: NSObject, NSWindowDelegate {
    private let panel = ShelfPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let content: NSHostingView<ShelfView>
    private var anchor = NSRect.zero
    private var monitors: [Any] = []
    private let logger = Logger(subsystem: "dev.nathanlanger.Nook", category: "Shelf")

    init(model: NookModel) {
        content = NSHostingView(rootView: ShelfView(model: model))
        super.init()
        panel.title = "Nook shelf"
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = content
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            guard let self, self.isShown else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.performClose(nil); return nil }
            } else { self.dismissIfOutside() }
            return event
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.dismissIfOutside()
        }) { monitors.append(monitor) }
    }

    var isShown: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }

    func show(below button: NSStatusBarButton) {
        guard let statusWindow = button.window else { return }
        anchor = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let centre = NSPoint(x: anchor.midX, y: anchor.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(centre) }) ?? statusWindow.screen else { return }
        content.layoutSubtreeIfNeeded()
        let menuHeight = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
        let frame = ShelfPlacement.frame(size: content.fittingSize, icon: anchor, screen: screen.frame, menuBarHeight: menuHeight)
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        logger.debug("Shelf shown: icon=\(NSStringFromRect(self.anchor), privacy: .public) panel=\(NSStringFromRect(frame), privacy: .public) screen=\(NSStringFromRect(screen.frame), privacy: .public) menuHeight=\(menuHeight, privacy: .public)")
    }

    func performClose(_ sender: Any?) {
        let wasShown = isShown
        panel.orderOut(sender)
        if wasShown { logger.debug("Shelf dismissed: visible=\(self.isShown, privacy: .public)") }
    }

    func windowDidResignKey(_ notification: Notification) {
        // A click on Nook must reach the toggle while the shelf is still open.
        if !anchor.contains(NSEvent.mouseLocation) { performClose(nil) }
    }

    private func dismissIfOutside() {
        guard isShown else { return }
        let point = NSEvent.mouseLocation
        // Let the status button itself handle the second click as a toggle.
        if !panel.frame.contains(point), !anchor.contains(point) { performClose(nil) }
    }

    deinit { monitors.forEach(NSEvent.removeMonitor) }
}

private final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(sender) }
}
