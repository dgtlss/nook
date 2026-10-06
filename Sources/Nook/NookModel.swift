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
    @Published var shortcutIssue: String?
    @Published private(set) var controlReachable = false

    let ownID = Bundle.main.bundleIdentifier ?? "dev.nathanlanger.Nook"
    let storeURL: URL
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
        entries = preferences.remembered.map { AppEntry(id: $0.id, name: $0.name, isRunning: false) }
    }

    var hiddenCount: Int { entries.filter { preferences.place(for: $0.id) != .visible }.count }
    var status: String {
        if !permissionGranted { return "Accessibility permission required." }
        if let message { return message }
        if applying { return "Updating your menu bar…" }
        switch reveal {
        case .tucked: return hiddenCount == 0 ? "Choose apps to hide." : "\(hiddenCount) \(hiddenCount == 1 ? "app" : "apps") hidden."
        case .peek: return "Hidden apps are shown."
        case .everything: return "All apps are visible."
        }
    }
    var sortedEntries: [AppEntry] {
        let indices = Dictionary(preferences.order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return entries.sorted { (indices[$0.id] ?? .max) < (indices[$1.id] ?? .max) }
    }
    func filtered(_ place: Place) -> [AppEntry] {
        sortedEntries.filter { preferences.place(for: $0.id) == place && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search)) }
    }
    func icon(_ id: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: "Application")!
    }
    func start() {
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
            entries = preferences.remembered.map { AppEntry(id: $0.id, name: $0.name, isRunning: running.contains($0.id)) }
            if preferences != previous { save() }
            if reveal != .everything, !applying { apply(reveal) }
        }
    }
    func assign(_ id: String, to place: Place, before target: String? = nil) {
        preferences.assign(id, to: place, ownID: ownID)
        if let target { preferences.move(id, before: target) }
        save()
        if reveal != .everything { apply(reveal) }
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
        if !preferences.rehide { hideTimer?.cancel() }
        else if reveal == .peek && !manualReveal { scheduleRehide() }
    }
    func toggle() {
        if shelfIsShown?() == true { tuck(); return }
        if reveal == .tucked { peek(automaticallyRehide: false) } else { tuck() }
    }
    func tuck() {
        manualReveal = false
        closeShelf?(); hideTimer?.cancel(); temporary.removeAll()
        apply(.tucked)
    }
    func peek(automaticallyRehide: Bool = true) {
        manualReveal = !automaticallyRehide
        hideTimer?.cancel()
        if preferences.useShelf {
            showShelf?(); scheduleRehide(); return
        }
        apply(.peek); scheduleRehide()
    }
    func showEverything() {
        manualReveal = false
        closeShelf?(); hideTimer?.cancel(); temporary.removeAll(); message = nil; restoreAll()
    }
    func revealApp(_ id: String) {
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
            if !pressed { message = "\(entries.first { $0.id == id }?.name ?? "The app") is visible in the menu bar. Click its icon to open it." }
            closeShelf?()
            scheduleRehide()
        }
    }
    func apply(_ requested: Reveal) {
        guard requested != .everything else { restoreAll(); return }
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
        let plan = VisibilityPlan(preferences: preferences, runningBundles: running, reveal: requested, ownID: ownID, temporary: temporary)
        // Shelf presentation does not change visibility. Releasing an identical
        // assertion would briefly reveal every icon before hiding them again.
        // Clearing a temporary reveal still produces a different plan below.
        if plan == currentPlan {
            if reveal != requested { reveal = requested; stateChanged?() }
            visibilityLogger.debug("Retained visibility lease: generation=\(self.generation, privacy: .public)")
            return
        }
        guard !plan.hidden.isEmpty else { restoreAll(); reveal = requested; stateChanged?(); return }
        generation += 1
        let ticket = generation
        pending?.restore(); pending = nil; timeout?.cancel()
        // MenuBarAgent combines simultaneous assertions. Release the previous
        // allow-list before requesting another, so a peek can reveal apps.
        let replacing = active != nil
        visibilityLogger.debug("Applying visibility: generation=\(ticket, privacy: .public) replacing=\(replacing, privacy: .public) hiddenCount=\(plan.hidden.count, privacy: .public)")
        active?.restore(); active = nil; currentPlan = nil
        applying = true; message = nil
        Task {
            if replacing { try? await Task.sleep(for: .milliseconds(250)) }
            guard ticket == generation else { return }
            begin(plan: plan, requested: requested, ticket: ticket)
        }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, ticket == self.generation else { return }
            self.fail("macOS didn’t respond. All your icons have been restored.")
        }
    }
    private func begin(plan: VisibilityPlan, requested: Reveal, ticket: Int) {
        pending = NookVisibilityLease.allowBundles(plan.allowed.sorted()) { [weak self] error in
            Task { @MainActor in
                guard let self, ticket == self.generation else { return }
                self.timeout?.cancel()
                if let error { self.fail("Couldn’t hide icons: \(error.localizedDescription)"); return }
                self.active = self.pending; self.pending = nil
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
                    let names = entries.filter { missing.contains($0.id) }.map(\.name).joined(separator: ", ")
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
    func suspend() { hideTimer?.cancel(); closeShelf?(); restoreAll() }
    func shutdown() {
        guard !didRestoreBeforeExit else { return }
        didRestoreBeforeExit = true
        refreshTask?.cancel(); hideTimer?.cancel(); restoreAll(); save()
    }
    func scheduleRehide() {
        hideTimer?.cancel()
        guard preferences.rehide, !manualReveal else { return }
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
            showEverything(); preferences = loaded.validated(); entries = preferences.remembered; save(); refresh(); stateChanged?()
        } catch { message = "Couldn’t read those settings: \(error.localizedDescription)" }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case organise = "Organise", behaviour = "Behaviour", appearance = "Appearance", about = "About Nook"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .organise: return "square.grid.2x2"; case .behaviour: return "cursorarrow.rays"; case .appearance: return "paintpalette"; case .about: return "face.smiling" }
    }
}
