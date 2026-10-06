// An original disposable menu bar app for live integration testing.
// No permissions, persistence, or network access.
import AppKit

@MainActor final class Fixture: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var items: [NSStatusItem] = []
    var window: NSWindow?
    var label: NSTextField?
    var openings = 0
    func applicationDidFinishLaunching(_ notification: Notification) {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Nook Test"
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = name.hasSuffix("A") ? "Nα" : "Nβ"
        item.button?.setAccessibilityLabel(name)
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "\(name) menu opened", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Quit fixture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu; items.append(item)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 110), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = name; window.isReleasedWhenClosed = false
        let label = NSTextField(wrappingLabelWithString: "\(name) is a temporary app for testing Nook’s hide/reveal. Its status item reads \(name.hasSuffix("A") ? "Nα" : "Nβ").")
        label.frame = NSRect(x: 18, y: 18, width: 304, height: 70)
        window.contentView?.addSubview(label); window.center(); window.makeKeyAndOrderFront(nil)
        self.window = window; self.label = label
        let appMenu = NSMenu()
        let root = NSMenuItem(); root.submenu = NSMenu()
        root.submenu?.addItem(withTitle: "Quit fixture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(root); NSApp.mainMenu = appMenu
    }
    func menuWillOpen(_ menu: NSMenu) {
        openings += 1
        label?.stringValue = "Status menu opened \(openings) time(s)."
    }
}

@main struct TestFixture {
    @MainActor static func main() {
        let delegate = Fixture()
        let app = NSApplication.shared; app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
