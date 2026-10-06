import AppKit
import ApplicationServices
import NookCore

struct MenuNode {
    var bundle: String
    var label: String
    var element: AXUIElement
    var rect: CGRect?
}

struct MenuSnapshot {
    var entries: [AppEntry]
    var nodes: [MenuNode]
    var systemLabels: Set<String>
}

/// Discovers real menu bar participants through the Accessibility hierarchy.
/// Multiple status items from one app are one visibility group on macOS 27.
enum Discovery {
    static func read() -> MenuSnapshot {
        guard AXIsProcessTrusted() else { return MenuSnapshot(entries: [], nodes: [], systemLabels: []) }
        var nodes: [MenuNode] = []
        var native: Set<String> = []
        var remaining = 900
        let apps = NSWorkspace.shared.runningApplications
        let candidates = apps.filter { $0.bundleIdentifier == "com.apple.MenuBarAgent" || $0.bundleIdentifier == "com.apple.controlcenter" }
        for app in candidates {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.15)
            inspect(root, depth: 0, owner: app.processIdentifier, budget: &remaining, nodes: &nodes, native: &native)
        }
        // Only use a legacy extras bar if MenuBarAgent is absent. Hidden app
        // extras can remain exposed by the app itself; they aren't proof of
        // current physical visibility on macOS 27.
        for app in apps where candidates.isEmpty && app.bundleIdentifier?.hasPrefix("com.apple.") == false {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.05)
            if let extras = attribute(root, kAXExtrasMenuBarAttribute as CFString), CFGetTypeID(extras) == AXUIElementGetTypeID() {
                inspect(extras as! AXUIElement, depth: 0, owner: app.processIdentifier, budget: &remaining, nodes: &nodes, native: &native)
            }
        }
        var unique: [String: AppEntry] = [:]
        for node in nodes where !node.bundle.hasPrefix("com.apple.") {
            let name = apps.first { $0.bundleIdentifier == node.bundle }?.localizedName ?? node.label
            unique[node.bundle] = AppEntry(id: node.bundle, name: name)
        }
        return MenuSnapshot(entries: unique.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, nodes: nodes, systemLabels: native)
    }

    private static func inspect(_ element: AXUIElement, depth: Int, owner: pid_t, budget: inout Int, nodes: inout [MenuNode], native: inout Set<String>) {
        guard depth < 9, budget > 0 else { return }
        budget -= 1
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let role = attribute(element, kAXRoleAttribute as CFString) as? String ?? ""
        let identifier = attribute(element, kAXIdentifierAttribute as CFString) as? String ?? ""
        let label = (attribute(element, kAXDescriptionAttribute as CFString) as? String)
            ?? (attribute(element, kAXTitleAttribute as CFString) as? String) ?? ""
        let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        if !bundle.isEmpty, !bundle.hasPrefix("com.apple."), (pid != owner || role == "AXMenuBarItem" || role == "AXButton" || role == "AXGroup") {
            nodes.append(MenuNode(bundle: bundle, label: label, element: element, rect: bounds(element)))
            // Stop at a participant boundary. Its children can expose the app's
            // entire window/menu hierarchy, which isn't menu bar discovery.
            return
        }
        if identifier.hasPrefix("com.apple.menuextra.") || (!label.isEmpty && bundle.hasPrefix("com.apple.") && (role == "AXMenuBarItem" || role == "AXButton")) {
            native.insert(identifier.isEmpty ? label : identifier)
        }
        for child in attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? [] {
            inspect(child, depth: depth + 1, owner: owner, budget: &budget, nodes: &nodes, native: &native)
        }
    }

    static func attribute(_ element: AXUIElement, _ key: CFString) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &result) == .success else { return nil }
        return result
    }

    static func bounds(_ element: AXUIElement) -> CGRect? {
        guard let p = attribute(element, kAXPositionAttribute as CFString), let s = attribute(element, kAXSizeAttribute as CFString), CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: point, size: size)
    }

    static func press(bundle: String) -> Bool {
        let snapshot = read()
        for node in snapshot.nodes where node.bundle == bundle {
            if pressIfSupported(node.element) { return true }
            // Resolve only the extras bar, never the app's ordinary menu bar.
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first {
                let root = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(root, 0.1)
                if let extras = attribute(root, kAXExtrasMenuBarAttribute as CFString), CFGetTypeID(extras) == AXUIElementGetTypeID() {
                    for child in attribute(extras as! AXUIElement, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? [] {
                        if pressIfSupported(child) { return true }
                    }
                }
            }
        }
        return false
    }

    private static func pressIfSupported(_ element: AXUIElement) -> Bool {
        var names: CFArray?
        AXUIElementCopyActionNames(element, &names)
        guard (names as? [String] ?? []).contains(kAXPressAction as String) else { return false }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    static func menuIsOpen() -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)
        guard let focused = attribute(system, kAXFocusedUIElementAttribute as CFString) else { return false }
        let element = focused as! AXUIElement
        let role = attribute(element, kAXRoleAttribute as CFString) as? String ?? ""
        return role == "AXMenu" || role == "AXMenuItem" || role == "AXMenuBarItem"
    }

    static func isEmptyMenuBar(at point: NSPoint) -> Bool {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(top - point.y), &found) == .success, let found else { return false }
        let role = attribute(found, kAXRoleAttribute as CFString) as? String ?? ""
        return role == "AXMenuBar" || role == "AXWindow"
    }
}
