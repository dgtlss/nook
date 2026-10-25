import AppKit
import SwiftUI
import Carbon
import NookCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = NookModel()
    private let updates = UpdateController()
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private lazy var quick: MenuPanelController<QuickView> = MenuPanelController(title: "Nook search", rootView: QuickView(model: model,
        openSettings: { [weak self] in self?.openSettings() },
        close: { [weak self] in self?.quick.performClose(nil) }))
    private lazy var shelf = MenuPanelController(title: "Nook shelf", rootView: ShelfView(model: model))
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private let shortcuts = ShortcutController()
    private let appearance = AppearanceController()
    private var lastGesture = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let appMenu = NSMenu()
        let root = NSMenuItem(); root.submenu = NSMenu(title: "Nook")
        root.submenu?.addItem(withTitle: "Nook Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        root.submenu?.addItem(withTitle: "Check for Updates…", action: #selector(UpdateController.checkForUpdates(_:)), keyEquivalent: "").target = updates
        root.submenu?.addItem(withTitle: "Show all menu bar apps", action: #selector(showAll), keyEquivalent: "") .target = self
        root.submenu?.addItem(.separator())
        #if DEBUG
        root.submenu?.addItem(withTitle: "Simulate missing menu control", action: #selector(simulateMissingControl), keyEquivalent: "").target = self
        #endif
        root.submenu?.addItem(withTitle: "Quit Nook", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(root)
        let edit = NSMenuItem(); edit.submenu = NSMenu(title: "Edit")
        edit.submenu?.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.submenu?.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo?.keyEquivalentModifierMask = [.command, .shift]
        edit.submenu?.addItem(.separator())
        for (title, selector, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.submenu?.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        appMenu.addItem(edit); NSApp.mainMenu = appMenu
        createStatusItem()
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
            self?.perform(action)
        }
        installMonitors()
        sync(); model.start()
        updates.beforeRelaunch = { [weak self] in self?.model.showEverything(); self?.appearance.clear() }
        updates.start()
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.quick.performClose(nil); self?.model.suspend(); self?.appearance.clear() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recreateStatusItem(); self?.model.recoverAfterEnvironmentChange() }
        })
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    if app?.bundleIdentifier == "com.apple.MenuBarAgent" {
                        // The old AppKit status window can survive a server
                        // restart while no longer representing its new button.
                        self.model.suspend()
                        if note.name == NSWorkspace.didLaunchApplicationNotification {
                            self.recreateStatusItem()
                            self.model.recoverAfterEnvironmentChange()
                        }
                    }
                    if note.name == NSWorkspace.activeSpaceDidChangeNotification {
                        self.quick.performClose(nil); self.shelf.performClose(nil); self.appearance.clear()
                    }
                    self.model.refresh(); self.sync()
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.quick.performClose(nil); self?.appearance.clear()
                self?.model.recoverAfterEnvironmentChange(); self?.sync()
            }
        })
        if model.showingSetup { openSettings() }
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
            window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 760, height: 580)
            window.contentView = NSHostingView(rootView: SettingsView(model: model, updates: updates)); window.center(); window.delegate = self
            window.setFrameAutosaveName("NookSettings")
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { model.undoManager }
    private func perform(_ action: ShortcutAction) {
        switch action { case .toggle: model.toggle(); case .search: showQuick(); case .showAll: model.showEverything() }
    }
    @objc private func showAll() { model.showEverything() }
    #if DEBUG
    @objc private func simulateMissingControl() { statusItem.isVisible = false }
    #endif
    @objc private func statusClicked() {
        // Accessibility activation has no mouse event. It must toggle too.
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true { showQuick() }
        else {
            quick.performClose(nil)
            if event?.modifierFlags.contains(.option) == true { model.showEverything() }
            else if !model.permissionGranted { openSettings() }
            else { model.toggle() }
        }
    }
    private func showQuick() {
        guard let button = statusItem.button else { return }
        shelf.performClose(nil); quick.show(below: button)
        NSApp.activate(ignoringOtherApps: true)
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
        shortcuts.configure(enabled: model.preferences.hotkeyEnabled && model.recordingShortcut == nil, bindings: model.preferences.shortcuts)
        if model.shortcutIssues != shortcuts.issues { model.shortcutIssues = shortcuts.issues }
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
            guard let self, self.model.preferences.hotkeyEnabled, self.model.recordingShortcut == nil else { return event }
            if let action = ShortcutAction.allCases.first(where: { self.model.preferences.shortcuts[$0].matches(event) }) {
                self.perform(action); return nil
            }
            return event
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown], handler: { [weak self] event in
            guard let self, self.model.permissionGranted, !self.model.isPaused, self.model.reveal == .tucked, Date().timeIntervalSince(self.lastGesture) > 0.6, self.isInMenuBar(NSEvent.mouseLocation) else { return }
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
            guard let self, self.model.permissionGranted, !self.model.isPaused, self.model.preferences.showOnHover, self.model.reveal == .tucked, Date().timeIntervalSince(self.lastGesture) > 0.8,
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
