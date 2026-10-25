import AppKit
import ApplicationServices
import Combine
import NookCore
import NookRuntime
import ServiceManagement
import os

@MainActor final class NookModel: ObservableObject {
    @Published var preferences: Preferences
    @Published private(set) var entries: [AppEntry] = []
    @Published private(set) var reveal: Reveal = .everything
    @Published private(set) var permissionGranted = AXIsProcessTrusted()
    @Published private(set) var applying = false
    @Published private(set) var message: String?
    @Published private(set) var available = NookVisibilityLease.isAvailable()
    @Published private(set) var lastVerified: Date?
    @Published private(set) var visibleIDs: Set<String> = []
    @Published var search = ""
    @Published var selectedPane: SettingsPane = .organise
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var shortcutIssues: [ShortcutAction: String] = [:]
    @Published var shortcutValidationIssues: [ShortcutAction: String] = [:]
    @Published var recordingShortcut: ShortcutAction? { didSet { stateChanged?() } }
    @Published var appFilter: AppFilter = .running
    @Published var showingSetup = false
    @Published private(set) var feedback: String?
    @Published private(set) var feedbackCanUndo = false
    @Published private(set) var now = Date()
    @Published private(set) var controlReachable = false

    let ownID = Bundle.main.bundleIdentifier ?? "dev.nathanlanger.Nook"
    let storeURL: URL
    let undoManager = UndoManager()
    private var active: NookVisibilityLease?
    private var pending: NookVisibilityLease?
    private var generation = 0
    private var timeout: Task<Void, Never>?
    private var hideTimer: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var temporary: Set<String> = []
    private var currentPlan: VisibilityPlan?
    private let visibilityLogger = Logger(subsystem: "dev.nathanlanger.Nook", category: "Visibility")
    private var refreshing = false
    private var didRestoreBeforeExit = false
    private var manualReveal = false
    private var missingControlSnapshots = 0
    private var pauseTimer: Task<Void, Never>?
    private var feedbackTimer: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var recoveryReveal: Reveal?
    private let icons = NSCache<NSString, NSImage>()
    var stateChanged: (() -> Void)?
    var showShelf: (() -> Void)?
    var closeShelf: (() -> Void)?
    var shelfIsShown: (() -> Bool)?
    var menuOpen: (() -> Bool)?
    var hoveringMenuBar: (() -> Bool)?
    var controlIsReachable: (() -> Bool)?

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Nook", isDirectory: true)
        storeURL = directory.appendingPathComponent("preferences.json")
        if let data = try? Data(contentsOf: storeURL), let saved = try? JSONDecoder().decode(Preferences.self, from: data) {
            preferences = saved.validated()
        } else {
            preferences = Preferences()
        }
        entries = preferences.remembered.map { AppEntry(id: $0.id, name: ApplicationIdentity.name(for: $0.id, fallback: $0.displayName), isRunning: false) }
        showingSetup = !preferences.setupCompleted
    }

    var hiddenCount: Int {
        guard !isPaused else { return 0 }
        let hidden = preferences.hiddenBundles(reveal: reveal, ownID: ownID, temporary: temporary)
        return entries.filter { $0.isRunning && hidden.contains($0.id) }.count
    }
    var isPaused: Bool { preferences.pause?.isActive(at: now) == true }
    var toggleTitle: String {
        if isPaused { return "Resume hiding" }
        return reveal == .tucked && shelfIsShown?() != true ? "Show hidden apps" : "Hide apps"
    }
    var visibleEntries: [AppEntry] {
        sortedEntries.filter { (appFilter == .all || $0.isRunning) && matches($0, query: search) }
    }
    var hasHiddenAssignments: Bool { preferences.assignments.values.contains { $0 != .visible } }
    var compatibility: String {
        available ? "Visibility controls are available." : "This macOS build does not provide Nook’s visibility controls."
    }
    var testedBuild: Bool { ProcessInfo.processInfo.operatingSystemVersionString.contains("26B5091g") }
    var status: String {
        if !permissionGranted { return "Accessibility permission required." }
        if let message { return message }
        if applying { return "Updating your menu bar…" }
        if isPaused {
            if let until = preferences.pause?.until { return "Paused until \(until.formatted(date: .omitted, time: .shortened)). All apps are visible." }
            return "Hiding paused. All apps are visible."
        }
        if shelfIsShown?() == true { return "Hidden apps are in the shelf." }
        switch reveal {
        case .tucked: return hiddenCount == 0 ? (hasHiddenAssignments ? "No running apps are hidden." : "Choose apps to hide.") : "\(hiddenCount) \(hiddenCount == 1 ? "app" : "apps") hidden."
        case .peek: return "Hidden apps are shown."
        case .everything: return "All apps are visible."
        }
    }
    var sortedEntries: [AppEntry] {
        let indices = Dictionary(preferences.order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return entries.sorted {
            let left = indices[$0.id] ?? .max, right = indices[$1.id] ?? .max
            return left == right ? $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending : left < right
        }
    }
    func filtered(_ place: Place) -> [AppEntry] {
        visibleEntries.filter { preferences.place(for: $0.id) == place }
    }
    func matches(_ entry: AppEntry, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || entry.displayName.localizedCaseInsensitiveContains(query) || entry.id.localizedCaseInsensitiveContains(query)
    }
    func icon(_ id: String) -> NSImage {
        if let icon = icons.object(forKey: id as NSString) { return icon }
        let icon = ApplicationIdentity.url(for: id).map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: "Application")!
        icons.setObject(icon, forKey: id as NSString)
        return icon
    }
    func start() {
        updatePause()
        refresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                self?.refresh()
            }
        }
    }
    func refresh() {
        now = Date()
        if preferences.pause != nil && !isPaused { resumeHiding(); return }
        controlReachable = controlIsReachable?() == true
        if currentPlan != nil, !applying, !controlReachable {
            fail("Nook’s icon became unavailable. Your apps have been restored. Reopen Nook if you need its controls.")
        }
        let trusted = AXIsProcessTrusted()
        if permissionGranted && !trusted { restoreAll(); message = "Accessibility was turned off. Your icons have been restored." }
        permissionGranted = trusted
        guard trusted, !refreshing else { return }
        refreshing = true
        Task {
            let snapshot = await Task.detached(priority: .utility) { Discovery.read() }.value
            refreshing = false
            visibleIDs = Set(snapshot.entries.map(\.id))
            // AppKit can report isVisible while MenuBarAgent has filtered our
            // item out. Check the host's participant list throughout a lease.
            if currentPlan != nil, !applying {
                missingControlSnapshots = visibleIDs.contains(ownID) ? 0 : missingControlSnapshots + 1
                if missingControlSnapshots >= 2 {
                    fail("macOS hid Nook’s toggle. Your apps have been restored. Run the installed Nook in Applications.")
                }
            } else { missingControlSnapshots = 0 }
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            let previous = preferences
            preferences.remember(snapshot.entries.filter { $0.id != ownID })
            entries = preferences.remembered.map { AppEntry(id: $0.id, name: ApplicationIdentity.name(for: $0.id, fallback: $0.displayName), isRunning: running.contains($0.id)) }
            if preferences != previous { save() }
            if reveal != .everything, !applying, !isPaused { apply(reveal) }
            stateChanged?()
        }
    }
    func assign(_ id: String, to place: Place, before target: String? = nil) {
        guard entries.contains(where: { $0.id == id }), id != ownID, !id.hasPrefix("com.apple.") else { return }
        guard preferences.place(for: id) != place || target != nil else { return }
        let previous = preferences.organisationState(for: id)
        preferences.assign(id, to: place, ownID: ownID)
        if let target { preferences.move(id, before: target) }
        guard preferences.organisationState(for: id) != previous else { return }
        registerUndo(previous, action: "Move \(name(for: id))")
        save()
        showFeedback("\(name(for: id)) moved to \(place.title.lowercased()).", undoable: true)
        if reveal != .everything, !isPaused { apply(reveal) }
    }
    func forget(_ id: String) {
        guard let entry = entries.first(where: { $0.id == id }), !entry.isRunning else { return }
        let previous = preferences.organisationState(for: id)
        preferences.forget(id); entries.removeAll { $0.id == id }
        registerUndo(previous, action: "Forget \(entry.displayName)")
        save(); showFeedback("Forgot \(entry.displayName).", undoable: true)
    }
    func move(_ id: String, by offset: Int, runningOnly: Bool = false) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        let peers = sortedEntries.filter { preferences.place(for: $0.id) == preferences.place(for: entry.id) && (!runningOnly || $0.isRunning) }
        guard let index = peers.firstIndex(where: { $0.id == id }), peers.indices.contains(index + offset) else { return }
        let target = offset < 0 ? peers[index + offset].id : (peers.indices.contains(index + offset + 1) ? peers[index + offset + 1].id : nil)
        let previous = preferences.organisationState(for: id)
        preferences.move(id, before: target)
        registerUndo(previous, action: "Reorder \(entry.displayName)")
        save(); showFeedback("Reordered \(entry.displayName).", undoable: true)
    }
    private func registerUndo(_ state: AppOrganisationState, action: String) {
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.restoreOrganisation(state, action: action) }
        }
        undoManager.setActionName(action)
    }
    private func restoreOrganisation(_ state: AppOrganisationState, action: String) {
        registerUndo(preferences.organisationState(for: state.id), action: action)
        preferences.restore(state)
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        entries = preferences.remembered.map { AppEntry(id: $0.id, name: ApplicationIdentity.name(for: $0.id, fallback: $0.displayName), isRunning: running.contains($0.id)) }
        save(); showFeedback("Restored \(name(for: state.id)).")
        if reveal != .everything, !isPaused { apply(reveal) }
    }
    func name(for id: String) -> String { entries.first { $0.id == id }?.displayName ?? id.split(separator: ".").last.map(String.init) ?? "App" }
    func showFeedback(_ text: String, undoable: Bool = false) {
        feedbackTimer?.cancel(); feedback = text; feedbackCanUndo = undoable
        feedbackTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.feedback = nil; self?.feedbackCanUndo = false
        }
    }
    func completeSetup() {
        preferences.setupCompleted = true; showingSetup = false; save()
    }
    func setShortcut(_ chord: KeyChord, for action: ShortcutAction) {
        guard chord.isValid else { shortcutValidationIssues[action] = "Include Command, Control or Option."; return }
        if let other = preferences.shortcuts.conflict(for: chord, excluding: action) {
            shortcutValidationIssues[action] = "Already used by \(other.title.lowercased())."; return
        }
        shortcutValidationIssues[action] = nil
        preferences.shortcuts[action] = chord; updatePreferences()
    }
    func resetShortcuts() {
        recordingShortcut = nil; shortcutValidationIssues = [:]
        preferences.shortcuts = ShortcutBindings(); updatePreferences()
    }
    func save() {
        do {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(preferences).write(to: storeURL, options: .atomic)
        } catch { message = "Couldn’t save settings: \(error.localizedDescription)" }
    }
    func updatePreferences() {
        preferences = preferences.validated(); save(); stateChanged?()
        updatePause()
        if !preferences.rehide { hideTimer?.cancel() }
        else if reveal == .peek && !manualReveal { scheduleRehide() }
    }
    func toggle() {
        if isPaused { resumeHiding(); return }
        if shelfIsShown?() == true { tuck(); return }
        if reveal == .tucked { peek(automaticallyRehide: false) } else { tuck() }
    }
    func tuck() {
        guard !isPaused else { return }
        recoveryTask?.cancel(); recoveryReveal = nil
        manualReveal = false
        closeShelf?(); hideTimer?.cancel(); temporary.removeAll()
        apply(.tucked)
    }
    func peek(automaticallyRehide: Bool = true) {
        guard !isPaused else { return }
        manualReveal = !automaticallyRehide
        hideTimer?.cancel()
        if preferences.useShelf {
            showShelf?(); scheduleRehide(); return
        }
        apply(.peek); scheduleRehide()
    }
    func showEverything() {
        recoveryTask?.cancel(); recoveryReveal = nil
        manualReveal = false
        closeShelf?(); hideTimer?.cancel(); temporary.removeAll(); message = nil; restoreAll()
    }
    func revealApp(_ id: String) {
        guard entries.contains(where: { $0.id == id && $0.isRunning }) else { return }
        temporary.insert(id)
        apply(reveal == .everything ? .everything : .tucked)
        let ticket = generation
        // Allow MenuBarAgent to publish the newly revealed accessibility element.
        Task {
            while applying && ticket == generation { try? await Task.sleep(for: .milliseconds(100)) }
            guard ticket == generation else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard ticket == generation else { return }
            let pressed = await Task.detached(priority: .userInitiated) { Discovery.press(bundle: id) }.value
            if !pressed { message = "\(name(for: id)) is visible in the menu bar. Click its icon to open it." }
            closeShelf?()
            scheduleRehide()
        }
    }
    func apply(_ requested: Reveal) {
        guard requested != .everything else { restoreAll(); return }
        guard !isPaused else { restoreAll(); return }
        guard permissionGranted else { message = "Enable Accessibility to organise your menu bar."; return }
        guard available else { message = "This macOS build doesn’t support Nook’s visibility controls."; return }
        // On the tested macOS build, the allow-list fails to retain Nook when
        // launched from the build folder. Never enter that known stranding state.
        let appPath = Bundle.main.bundleURL.standardizedFileURL.path
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        guard appPath.hasPrefix("/Applications/") || appPath.hasPrefix(userApplications + "/") else {
            fail("Install Nook in Applications to hide apps. All apps are visible.")
            return
        }
        guard controlIsReachable?() == true else {
            fail("Nook’s icon isn’t ready. Your apps are visible; reopen Nook to restore its control.")
            return
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let plan = VisibilityPlan(preferences: preferences, runningBundles: running, reveal: requested, ownID: ownID, temporary: temporary,
                                  previouslyAllowed: currentPlan?.allowed ?? [])
        // Shelf presentation does not change visibility. Releasing an identical
        // assertion would briefly reveal every icon before hiding them again.
        // Clearing a temporary reveal still produces a different plan below.
        if !applying, plan == currentPlan {
            if reveal != requested { reveal = requested; stateChanged?() }
            visibilityLogger.debug("Retained visibility lease: generation=\(self.generation, privacy: .public)")
            return
        }
        guard !plan.hidden.isEmpty else { restoreAll(); reveal = requested; stateChanged?(); return }
        generation += 1
        let ticket = generation
        pending?.restore(); pending = nil; timeout?.cancel()
        // Keep the active request while its replacement is activating. Releasing
        // it first briefly exposes every icon whenever a background app starts.
        // The old request is released in begin's completion, before verification.
        let replacing = active != nil
        visibilityLogger.debug("Applying visibility: generation=\(ticket, privacy: .public) replacing=\(replacing, privacy: .public) hiddenCount=\(plan.hidden.count, privacy: .public)")
        applying = true; message = nil
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, ticket == self.generation else { return }
            self.fail("macOS didn’t respond. All your icons have been restored.")
        }
        begin(plan: plan, requested: requested, ticket: ticket)
    }
    private func begin(plan: VisibilityPlan, requested: Reveal, ticket: Int) {
        pending = NookVisibilityLease.allowBundles(plan.allowed.sorted()) { [weak self] error in
            Task { @MainActor in
                guard let self, ticket == self.generation else { return }
                self.timeout?.cancel()
                if let error { self.fail("Couldn’t hide icons: \(error.localizedDescription)"); return }
                let previous = self.active
                self.active = self.pending; self.pending = nil
                // MenuBarAgent combines overlapping restrictions. Once the new
                // one is active, release the old one so newly allowed apps can
                // appear while apps hidden by both requests remain hidden.
                previous?.restore()
                self.currentPlan = plan; self.reveal = requested; self.applying = false
                self.stateChanged?()
                self.verify(plan: plan, ticket: ticket)
            }
        }
        if pending == nil { fail("macOS couldn’t start the visibility request."); return }
    }
    private func verify(plan: VisibilityPlan, ticket: Int) {
        Task {
            var failure = "Nook couldn’t verify the menu bar. All icons have been restored."
            // The assertion callback precedes the menu bar's AX publication.
            // Retry a bounded number of times before concluding it failed.
            for _ in 0..<6 {
                try? await Task.sleep(for: .milliseconds(400))
                guard ticket == generation else { return }
                let snapshot = await Task.detached(priority: .utility) { Discovery.read() }.value
                guard ticket == generation else { return }
                visibleIDs = Set(snapshot.entries.map(\.id))
                controlReachable = controlIsReachable?() == true
                let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
                let expected = Set(entries.map(\.id)).intersection(running).intersection(plan.allowed).union([ownID])
                let check = VisibilityCheck.evaluate(controlReachable: controlReachable,
                    snapshotAvailable: AXIsProcessTrusted() && (!snapshot.nodes.isEmpty || !snapshot.systemLabels.isEmpty),
                    visible: visibleIDs, hidden: plan.hidden, expected: expected)
                switch check {
                case .verified: lastVerified = Date(); return
                case .unavailableControl:
                    fail("Nook’s icon became unavailable. Your apps have been restored.")
                    return
                case .unavailableSnapshot: continue
                case .unexpectedVisibility:
                    failure = "macOS kept the selected icons visible. Nook restored the menu bar; try again."
                case .missingApps(let missing):
                    if missing.contains(ownID) {
                        failure = "macOS hid Nook’s toggle. Your apps have been restored. Run the installed Nook in Applications."
                        continue
                    }
                    let names = entries.filter { missing.contains($0.id) }.map(\.displayName).joined(separator: ", ")
                    failure = "macOS didn’t reveal \(names). Nook restored the menu bar; try again."
                }
            }
            fail(failure)
        }
    }
    private func fail(_ text: String) {
        restoreAll(); message = text
    }
    func restoreAll() {
        hideTimer?.cancel(); hideTimer = nil
        generation += 1; timeout?.cancel(); timeout = nil
        pending?.restore(); pending = nil; active?.restore(); active = nil
        currentPlan = nil; applying = false; reveal = .everything
        missingControlSnapshots = 0
        stateChanged?()
    }
    func pauseHiding(minutes: Int? = nil) {
        showEverything()
        preferences.pause = HidingPause(until: minutes.map { Date().addingTimeInterval(Double($0) * 60) })
        now = Date(); save(); updatePause(); stateChanged?()
    }
    func resumeHiding() {
        pauseTimer?.cancel(); preferences.pause = nil; now = Date()
        save(); stateChanged?()
        if controlIsReachable?() == true, visibleIDs.contains(ownID) { tuck() }
        else { recoveryReveal = .tucked; recoverAfterEnvironmentChange() }
    }
    private func updatePause() {
        pauseTimer?.cancel()
        guard let pause = preferences.pause else { return }
        if !pause.isActive(at: Date()) { resumeHiding(); return }
        if reveal != .everything { restoreAll() }
        guard let until = pause.until else { return }
        pauseTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.resumeHiding()
        }
    }
    func suspend() {
        recoveryTask?.cancel(); recoveryReveal = recoveryReveal ?? reveal
        hideTimer?.cancel(); closeShelf?(); restoreAll()
    }
    func recoverAfterEnvironmentChange() {
        let desired = recoveryReveal ?? reveal
        recoveryTask?.cancel(); recoveryReveal = desired
        closeShelf?(); restoreAll()
        visibleIDs = []; refresh()
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            // A new screen or menu-bar host publishes its controls asynchronously.
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                if !self.refreshing, self.controlIsReachable?() == true, self.visibleIDs.contains(self.ownID) {
                    self.recoveryReveal = nil
                    if !self.isPaused, desired != .everything {
                        self.apply(desired)
                        if desired == .peek { self.scheduleRehide() }
                    }
                    return
                }
                if !self.refreshing { self.refresh() }
            }
            self.recoveryReveal = nil
            if desired != .everything { self.message = "Your apps are visible while the menu bar recovers. Try Hide apps when Nook’s control is available." }
        }
    }
    func copyDiagnostics() {
        let text = """
        Nook \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
        \(ProcessInfo.processInfo.operatingSystemVersionString)
        Displays: \(NSScreen.screens.count); notched: \(NSScreen.screens.filter { $0.safeAreaInsets.top > 0 }.count)
        Accessibility: \(permissionGranted ? "enabled" : "disabled")
        Visibility backend: \(available ? "available" : "unavailable")
        Nook control: \(controlReachable ? "available" : "unavailable")
        State: \(isPaused ? "paused" : reveal.rawValue)
        Running menu bar apps: \(entries.filter(\.isRunning).count)
        Apps hidden by Nook: \(hiddenCount)
        Shortcut conflicts: \(shortcutIssues.count)
        Last verified: \(lastVerified?.formatted(.iso8601) ?? "not yet")
        Validated OS build: 27.2 (26B5091g)
        """
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        showFeedback("Diagnostic summary copied. It contains no app names or menu contents.")
    }
    func shutdown() {
        guard !didRestoreBeforeExit else { return }
        didRestoreBeforeExit = true
        refreshTask?.cancel(); hideTimer?.cancel(); pauseTimer?.cancel(); feedbackTimer?.cancel(); recoveryTask?.cancel()
        restoreAll(); save()
    }
    func scheduleRehide() {
        hideTimer?.cancel()
        guard preferences.rehide, !manualReveal, !isPaused else { return }
        hideTimer = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(preferences.rehideDelay))
            while !Task.isCancelled && (menuOpen?() == true || hoveringMenuBar?() == true) {
                try? await Task.sleep(for: .milliseconds(600))
            }
            guard !Task.isCancelled else { return }
            tuck()
        }
    }
    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch { message = "Couldn’t change launch at login: \(error.localizedDescription)"; launchAtLogin = SMAppService.mainApp.status == .enabled }
    }
    func exportSettings() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Nook-settings.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(preferences).write(to: url, options: .atomic) }
        catch { message = error.localizedDescription }
    }
    func importSettings() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let loaded = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url))
            guard loaded.schema == 1 else { message = "These settings are from a newer Nook version."; return }
            showEverything(); undoManager.removeAllActions()
            preferences = loaded.validated(); entries = preferences.remembered; save(); updatePause(); refresh(); stateChanged?()
        } catch { message = "Couldn’t read those settings: \(error.localizedDescription)" }
    }
}

enum AppFilter: String, CaseIterable, Identifiable {
    case running = "Running", all = "All apps"
    var id: String { rawValue }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case organise = "Organise", behaviour = "Behaviour", appearance = "Appearance", about = "About Nook"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .organise: return "square.grid.2x2"; case .behaviour: return "cursorarrow.rays"; case .appearance: return "paintpalette"; case .about: return "face.smiling" }
    }
}
