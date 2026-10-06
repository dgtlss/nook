import AppKit
import NookCore
import os

@MainActor final class AppearanceController {
    private var panels: [NSPanel] = []
    private var lastSettings: Preferences?
    private var lastScreens: [ScreenGeometry] = []
    private let logger = Logger(subsystem: "dev.nathanlanger.Nook", category: "Appearance")
    private struct ScreenGeometry: Equatable {
        let frame: CGRect
        let safeAreaTop: CGFloat
        let menuBarHeight: CGFloat
        init(_ screen: NSScreen) {
            frame = screen.frame
            safeAreaTop = screen.safeAreaInsets.top
            menuBarHeight = max(NSStatusBar.system.thickness, safeAreaTop)
        }
    }
    func update(_ preferences: Preferences) {
        let screens = NSScreen.screens.map(ScreenGeometry.init)
        guard lastSettings?.tintEnabled != preferences.tintEnabled || lastSettings?.tintHex != preferences.tintHex || lastSettings?.tintOpacity != preferences.tintOpacity || lastSettings?.shape != preferences.shape || lastSettings?.borderEnabled != preferences.borderEnabled || lastSettings?.shadowEnabled != preferences.shadowEnabled || screens != lastScreens else { return }
        clear(); lastSettings = preferences; lastScreens = screens
        guard preferences.tintEnabled || preferences.borderEnabled || preferences.shadowEnabled else { return }
        for screen in screens {
            let height = screen.menuBarHeight
            let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
            let panel = TintPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Nook menu bar tint"
            // Above the menu bar background, below its status controls.
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) - 1)
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.ignoresMouseEvents = true; panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.isReleasedWhenClosed = false
            panel.contentView = TintView(preferences: preferences, notch: screen.safeAreaTop > 0)
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless(); panels.append(panel)
            logger.debug("Tint placed: requested=\(NSStringFromRect(frame), privacy: .public) actual=\(NSStringFromRect(panel.frame), privacy: .public) screen=\(NSStringFromRect(screen.frame), privacy: .public) level=\(panel.level.rawValue, privacy: .public)")
        }
    }
    func clear() { panels.forEach { $0.orderOut(nil) }; panels.removeAll(); lastSettings = nil; lastScreens = [] }
}

/// Ordinary windows are constrained to the usable desktop, below the menu bar.
/// This mouse-transparent decoration deliberately occupies the menu bar itself.
private final class TintPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class TintView: NSView {
    let preferences: Preferences
    let notch: Bool
    init(preferences: Preferences, notch: Bool) { self.preferences = preferences; self.notch = notch; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0 else { return }
        let n = UInt64(preferences.tintHex, radix: 16) ?? 0x146B60
        let color = NSColor(calibratedRed: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: preferences.tintOpacity)
        let inset = preferences.shape == .full ? 0.0 : 3.0
        let radius = preferences.shape == .full ? 0.0 : 9.0
        let rect = bounds.insetBy(dx: inset, dy: preferences.shape == .full ? 0 : 2)
        var paths: [NSBezierPath]
        if preferences.shape == .split {
            let gap = notch ? 190.0 : 28.0
            paths = [NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: rect.width / 2 - gap / 2, height: rect.height), xRadius: radius, yRadius: radius), NSBezierPath(roundedRect: NSRect(x: rect.midX + gap / 2, y: rect.minY, width: rect.width / 2 - gap / 2, height: rect.height), xRadius: radius, yRadius: radius)]
        } else { paths = [NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)] }
        for path in paths {
            NSGraphicsContext.saveGraphicsState()
            if preferences.shadowEnabled { let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.15); shadow.shadowBlurRadius = 5; shadow.shadowOffset = NSSize(width: 0, height: -2); shadow.set() }
            if preferences.tintEnabled { color.setFill(); path.fill() }
            if preferences.borderEnabled { color.withAlphaComponent(0.35).setStroke(); path.lineWidth = 0.7; path.stroke() }
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
