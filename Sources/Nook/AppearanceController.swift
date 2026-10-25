import AppKit
import SwiftUI
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
        let notch: CGRect?
        init(_ screen: NSScreen) {
            frame = screen.frame
            safeAreaTop = screen.safeAreaInsets.top
            menuBarHeight = max(NSStatusBar.system.thickness, safeAreaTop)
            notch = screen.menuBarNotch
        }
    }
    func update(_ preferences: Preferences) {
        // Avoid leaving a decorative strip over a full-screen app's hidden bar.
        if NSApp.currentSystemPresentationOptions.contains(.autoHideMenuBar)
            || NSApp.currentSystemPresentationOptions.contains(.hideMenuBar) {
            if !panels.isEmpty { clear() }
            return
        }
        let screens = NSScreen.screens.map(ScreenGeometry.init)
        guard lastSettings?.tintEnabled != preferences.tintEnabled || lastSettings?.tintHex != preferences.tintHex || lastSettings?.tintOpacity != preferences.tintOpacity || lastSettings?.shape != preferences.shape || lastSettings?.borderEnabled != preferences.borderEnabled || lastSettings?.shadowEnabled != preferences.shadowEnabled || screens != lastScreens else { return }
        clear(); lastSettings = preferences; lastScreens = screens
        guard preferences.tintEnabled || preferences.borderEnabled || preferences.shadowEnabled else { return }
        for screen in screens {
            let height = screen.menuBarHeight
            let shadowSpace: CGFloat = preferences.shadowEnabled ? 8 : 0
            let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height - shadowSpace, width: screen.frame.width, height: height + shadowSpace)
            let panel = TintPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Nook menu bar tint"
            // Above the menu bar background, below its status controls.
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) - 1)
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.ignoresMouseEvents = true; panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isReleasedWhenClosed = false
            let tint = MenuBarTintView(preferences: preferences, notch: screen.notch)
            tint.barHeight = height; panel.contentView = tint
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

final class MenuBarTintView: NSView {
    var preferences: Preferences
    var notch: CGRect?
    var barHeight: CGFloat?
    init(preferences: Preferences, notch: CGRect?) { self.preferences = preferences; self.notch = notch; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0 else { return }
        let n = UInt64(preferences.tintHex, radix: 16) ?? 0x146B60
        let color = NSColor(calibratedRed: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: preferences.tintOpacity)
        let radius = preferences.shape == .full ? 0.0 : 9.0
        let bar = CGRect(x: bounds.minX, y: bounds.maxY - min(barHeight ?? bounds.height, bounds.height),
                         width: bounds.width, height: min(barHeight ?? bounds.height, bounds.height))
        for rect in MenuBarGeometry.segments(in: bar, shape: preferences.shape, notch: notch) {
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            NSGraphicsContext.saveGraphicsState()
            if preferences.shadowEnabled {
                let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.15)
                shadow.shadowBlurRadius = 5; shadow.shadowOffset = NSSize(width: 0, height: -2)
                NSGraphicsContext.saveGraphicsState()
                shadow.set(); NSColor.black.setFill(); path.fill()
                NSGraphicsContext.restoreGraphicsState()
                // Keep only the shadow, so it also works when the tint is off.
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .clear; path.fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            if preferences.tintEnabled { color.setFill(); path.fill() }
            if preferences.borderEnabled { color.withAlphaComponent(0.35).setStroke(); path.lineWidth = 0.7; path.stroke() }
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

extension NSScreen {
    var menuBarNotch: CGRect? {
        guard safeAreaInsets.top > 0, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        return CGRect(x: left.maxX - frame.minX, y: 0, width: max(0, right.minX - left.maxX),
                      height: max(NSStatusBar.system.thickness, safeAreaInsets.top))
    }
}

/// The preview and actual menu bar use the same renderer and appearance values.
struct MenuBarTint: NSViewRepresentable {
    let preferences: Preferences
    var notch: CGRect? = nil
    var barHeight: CGFloat? = nil
    func makeNSView(context: Context) -> MenuBarTintView { MenuBarTintView(preferences: preferences, notch: notch) }
    func updateNSView(_ view: MenuBarTintView, context: Context) {
        view.preferences = preferences; view.notch = notch; view.barHeight = barHeight; view.needsDisplay = true
    }
}
