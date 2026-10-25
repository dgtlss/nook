import AppKit
import SwiftUI
import NookCore
import os

/// Status buttons are remotely hosted. Place both search and the shelf in
/// screen coordinates, including when a query changes the content height.
@MainActor final class MenuPanelController<Content: View>: NSObject, NSWindowDelegate {
    private let panel = ShelfPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let content: MenuHostingView<AnyView>
    private let rootView: Content
    private var anchor = NSRect.zero
    private var screen: NSScreen?
    private var monitors: [Any] = []
    private let logger = Logger(subsystem: "dev.nathanlanger.Nook", category: "Shelf")

    init(title: String, rootView: Content) {
        self.rootView = rootView
        content = MenuHostingView(rootView: AnyView(rootView))
        super.init()
        panel.title = title
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = content
        content.sizeChanged = { [weak self] in self?.resize() }
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
        self.screen = screen
        content.rootView = AnyView(rootView.id(UUID()))
        content.layoutSubtreeIfNeeded()
        resize(force: true)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isShown else { return }
            self.content.layoutSubtreeIfNeeded()
            if let field = self.searchField(in: self.content) { self.panel.makeFirstResponder(field) }
        }
        logger.debug("Menu panel shown: icon=\(NSStringFromRect(self.anchor), privacy: .public) panel=\(NSStringFromRect(self.panel.frame), privacy: .public)")
    }

    private func searchField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable, field.isEnabled { return field }
        for child in view.subviews {
            if let field = searchField(in: child) { return field }
        }
        return nil
    }

    private func resize(force: Bool = false) {
        guard force || isShown, let screen else { return }
        let size = content.fittingSize
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return }
        let menuHeight = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
        let frame = ShelfPlacement.frame(size: size, icon: anchor, screen: screen.frame, menuBarHeight: menuHeight)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
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

private final class MenuHostingView<Content: View>: NSHostingView<Content> {
    var sizeChanged: (() -> Void)?
    private var resizeQueued = false
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        guard !resizeQueued else { return }
        resizeQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resizeQueued = false; self.sizeChanged?()
        }
    }
}

private final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(sender) }
}
