import AppKit
import SwiftUI
import Carbon
import NookCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = NookModel()
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let quick = NSPopover()
    private lazy var shelf = ShelfController(model: model)
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private let shortcuts = ShortcutController()
    private let appearance = AppearanceController()
    private var lastGesture = Date.distantPast
    private var peekOnWake = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let appMenu = NSMenu()
        let root = NSMenuItem(); root.submenu = NSMenu(title: "Nook")
        root.submenu?.addItem(withTitle: "Nook Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        root.submenu?.addItem(withTitle: "Show all menu bar apps", action: #selector(showAll), keyEquivalent: "") .target = self
        root.submenu?.addItem(.separator())
        #if DEBUG
        root.submenu?.addItem(withTitle: "Simulate missing menu control", action: #selector(simulateMissingControl), keyEquivalent: "").target = self
        #endif
        root.submenu?.addItem(withTitle: "Quit Nook", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(root); NSApp.mainMenu = appMenu
        createStatusItem()
        quick.behavior = .transient
        quick.contentViewController = NSHostingController(rootView: QuickView(model: model, openSettings: { [weak self] in self?.openSettings() }))
        model.stateChanged = { [weak self] in self?.sync() }
        model.showShelf = { [weak self] in self?.showShelf() }
        model.closeShelf = { [weak self] in self?.shelf.performClose(nil) }
        model.shelfIsShown = { [weak self] in self?.shelf.isShown == true }
        model.hoveringMenuBar = { [weak self] in
            guard let self else { return false }
            let point = NSEvent.mouseLocation
            return self.isInMenuBar(point) || (self.shelf.isShown && self.shelf.frame.contains(point))
        }
        model.menuOpen = { Discovery.menuIsOpen() }
        model.controlIsReachable = { [weak self] in self?.isControlReachable == true }
        shortcuts.action = { [weak self] action in
            switch action { case 1: self?.model.toggle(); case 2: self?.showQuick(); case 3: self?.model.showEverything(); default: break }
        }
        installMonitors()
        sync(); model.start()
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.peekOnWake = self?.model.reveal == .tucked; self?.model.suspend(); self?.appearance.clear() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refresh(); if self?.peekOnWake == true { self?.model.tuck() }; self?.sync() }
        })
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    if app?.bundleIdentifier == "com.apple.MenuBarAgent" {
                        // The old AppKit status window can survive a server
                        // restart while no longer representing its new button.
                        self.model.showEverything()
                        if note.name == NSWorkspace.didLaunchApplicationNotification {
                            self.recreateStatusItem()
                        }
                    }
                    self.model.refresh(); self.sync()
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.shelf.performClose(nil); self?.sync(); self?.model.refresh() } })
        openSettings()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.showEverything()
        recreateStatusItem()
        openSettings()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown(); appearance.clear(); shortcuts.stop()
        monitors.forEach(NSEvent.removeMonitor)
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
    }
    @objc func openSettings() {
        quick.performClose(nil); shelf.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 660), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Nook"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 920, height: 610)
            window.contentView = NSHostingView(rootView: SettingsView(model: model)); window.center(); window.delegate = self
            window.setFrameAutosaveName("NookSettings")
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showAll() { model.showEverything() }
    #if DEBUG
    @objc private func simulateMissingControl() { statusItem.isVisible = false }
    #endif
    @objc private func statusClicked() {
        // Accessibility activation has no mouse event. It must toggle too.
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true { showQuick() }
        else if event?.modifierFlags.contains(.option) == true { model.showEverything() }
        else if !model.permissionGranted { openSettings() }
        else { model.toggle() }
    }
    private func showQuick() {
        guard let button = statusItem.button else { return }
        shelf.performClose(nil); quick.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        quick.contentViewController?.view.window?.makeKey(); NSApp.activate(ignoringOtherApps: true)
    }
    private func showShelf() {
        guard let button = statusItem.button else { return }
        quick.performClose(nil)
        shelf.show(below: button)
    }
    private func sync() {
        statusItem?.isVisible = true
        statusItem?.button?.image = MenuBarArtwork.image(model.preferences.menuBarIcon, peeking: model.reveal != .tucked)
        statusItem?.button?.toolTip = "Nook — \(model.status)\nClick to toggle hidden apps. Option-click to show all. Right-click for controls."
        shortcuts.configure(enabled: model.preferences.hotkeyEnabled)
        model.shortcutIssue = shortcuts.registrationFailure
        appearance.update(model.preferences)
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 27)
        statusItem.autosaveName = "NookControl"
        statusItem.behavior = [] // The reveal control must not be Command-drag removable.
        statusItem.isVisible = true
        statusItem.button?.target = self; statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.setAccessibilityLabel("Nook")
    }
    private func recreateStatusItem() {
        quick.performClose(nil); shelf.performClose(nil)
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        createStatusItem(); sync()
    }
    private var isControlReachable: Bool {
        guard let statusItem, statusItem.isVisible, let window = statusItem.button?.window,
              window.isVisible, window.frame.width > 0, window.frame.height > 0 else { return false }
        return NSScreen.screens.contains { screen in
            let height = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
            let bar = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
            let centre = NSPoint(x: window.frame.midX, y: window.frame.midY)
            guard bar.contains(centre) else { return false }
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                return left.contains(centre) || right.contains(centre)
            }
            return true
        }
    }
    private func installMonitors() {
        // App-local key events also support shortcuts while Settings is focused.
        // Carbon handles the system-wide route; macOS consumes those events.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, self.model.preferences.hotkeyEnabled else { return event }
            let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
            if flags == [.control, .option], event.keyCode == UInt16(kVK_ANSI_N) { self.model.toggle(); return nil }
            if flags == [.control, .option], event.keyCode == UInt16(kVK_Space) { self.showQuick(); return nil }
            if flags == [.control, .option, .shift], event.keyCode == UInt16(kVK_ANSI_N) { self.model.showEverything(); return nil }
            return event
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown], handler: { [weak self] event in
            guard let self, self.model.permissionGranted, self.model.reveal == .tucked, Date().timeIntervalSince(self.lastGesture) > 0.6, self.isInMenuBar(NSEvent.mouseLocation) else { return }
            if event.type == .scrollWheel, self.model.preferences.showOnScroll, abs(event.scrollingDeltaY) > 1 {
                self.lastGesture = Date(); self.model.peek()
            } else if event.type == .leftMouseDown, self.model.preferences.showOnEmptyClick {
                let point = NSEvent.mouseLocation
                Task {
                    let empty = await Task.detached { Discovery.isEmptyMenuBar(at: point) }.value
                    if empty { self.lastGesture = Date(); self.model.peek() }
                }
            }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            guard let self, self.model.permissionGranted, self.model.preferences.showOnHover, self.model.reveal == .tucked, Date().timeIntervalSince(self.lastGesture) > 0.8,
                let frame = self.statusItem.button?.window?.frame, frame.insetBy(dx: -7, dy: 0).contains(NSEvent.mouseLocation) else { return }
            self.lastGesture = Date(); self.model.peek()
        }) { monitors.append(monitor) }
    }
    private func isInMenuBar(_ point: NSPoint) -> Bool {
        NSScreen.screens.contains { screen in
            guard screen.frame.contains(point) else { return false }
            let height = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
            return point.y >= screen.frame.maxY - height
        }
    }
}

@MainActor final class ShortcutController {
    var action: ((Int) -> Void)?
    private(set) var registrationFailure: String?
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var enabled = false
    func configure(enabled: Bool) {
        guard self.enabled != enabled else { return }
        stop(); self.enabled = enabled
        guard enabled else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetEventDispatcherTarget(), { _, event, data in
            guard let event, let data else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr else { return result }
            MainActor.assumeIsolated { Unmanaged<ShortcutController>.fromOpaque(data).takeUnretainedValue().action?(Int(id.id)) }
            return noErr
        }, 1, &spec, context, &handler)
        guard installed == noErr else {
            registrationFailure = "macOS couldn’t enable global shortcuts (\(installed))."
            return
        }
        for (id, key, modifiers) in [(1, UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey)), (2, UInt32(kVK_Space), UInt32(controlKey | optionKey)), (3, UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey | shiftKey))] {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: 0x4E4F4F4B, id: UInt32(id)), GetEventDispatcherTarget(), 0, &ref)
            if result == noErr, let ref { refs.append(ref) }
            else { registrationFailure = "A global shortcut is unavailable (\(result)). Another app may be using it." }
        }
    }
    func stop() {
        refs.forEach { UnregisterEventHotKey($0) }; refs = []
        if let handler { RemoveEventHandler(handler) }; handler = nil; enabled = false
        registrationFailure = nil
    }
}
