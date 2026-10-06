import Foundation

public enum Place: String, Codable, CaseIterable, Identifiable, Sendable {
    case visible, tucked, quiet
    public var id: String { rawValue }
    public var title: String {
        switch self { case .visible: return "Visible"; case .tucked: return "Hidden"; case .quiet: return "Always hidden" }
    }
    public var symbol: String {
        switch self { case .visible: return "sun.max"; case .tucked: return "tray"; case .quiet: return "moon" }
    }
}

public enum Reveal: String, Codable, Sendable {
    case tucked, peek, everything
    public func includes(_ place: Place) -> Bool {
        switch self {
        case .tucked: return place == .visible
        case .peek: return place != .quiet
        case .everything: return true
        }
    }
}

public struct AppEntry: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var isRunning: Bool
    public init(id: String, name: String, isRunning: Bool = true) {
        self.id = id; self.name = name; self.isRunning = isRunning
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var schema = 1
    public var assignments: [String: Place] = [:]
    public var order: [String] = []
    public var remembered: [AppEntry] = []
    public var rehide = true
    public var rehideDelay = 8.0
    public var showOnHover = false
    public var showOnScroll = true
    public var showOnEmptyClick = false
    public var useShelf = false
    public var tintEnabled = false
    public var tintOpacity = 0.14
    public var tintHex = "146B60"
    public var borderEnabled = false
    public var shadowEnabled = false
    public var shape: BarShape = .full
    public var hotkeyEnabled = true
    public var menuBarIcon: MenuBarIcon = .nook
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case schema, assignments, order, remembered, rehide, rehideDelay
        case showOnHover, showOnScroll, showOnEmptyClick, useShelf
        case tintEnabled, tintOpacity, tintHex, borderEnabled, shadowEnabled
        case shape, hotkeyEnabled, menuBarIcon
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? schema
        assignments = try c.decodeIfPresent([String: Place].self, forKey: .assignments) ?? assignments
        order = try c.decodeIfPresent([String].self, forKey: .order) ?? order
        remembered = try c.decodeIfPresent([AppEntry].self, forKey: .remembered) ?? remembered
        rehide = try c.decodeIfPresent(Bool.self, forKey: .rehide) ?? rehide
        rehideDelay = try c.decodeIfPresent(Double.self, forKey: .rehideDelay) ?? rehideDelay
        showOnHover = try c.decodeIfPresent(Bool.self, forKey: .showOnHover) ?? showOnHover
        showOnScroll = try c.decodeIfPresent(Bool.self, forKey: .showOnScroll) ?? showOnScroll
        showOnEmptyClick = try c.decodeIfPresent(Bool.self, forKey: .showOnEmptyClick) ?? showOnEmptyClick
        useShelf = try c.decodeIfPresent(Bool.self, forKey: .useShelf) ?? useShelf
        tintEnabled = try c.decodeIfPresent(Bool.self, forKey: .tintEnabled) ?? tintEnabled
        tintOpacity = try c.decodeIfPresent(Double.self, forKey: .tintOpacity) ?? tintOpacity
        tintHex = try c.decodeIfPresent(String.self, forKey: .tintHex) ?? tintHex
        borderEnabled = try c.decodeIfPresent(Bool.self, forKey: .borderEnabled) ?? borderEnabled
        shadowEnabled = try c.decodeIfPresent(Bool.self, forKey: .shadowEnabled) ?? shadowEnabled
        shape = try c.decodeIfPresent(BarShape.self, forKey: .shape) ?? shape
        hotkeyEnabled = try c.decodeIfPresent(Bool.self, forKey: .hotkeyEnabled) ?? hotkeyEnabled
        if let name = try c.decodeIfPresent(String.self, forKey: .menuBarIcon) {
            menuBarIcon = MenuBarIcon(rawValue: name) ?? .nook
        }
    }
    public func place(for id: String) -> Place { assignments[id] ?? .visible }
    public mutating func assign(_ id: String, to place: Place, ownID: String) {
        guard !id.isEmpty, id != ownID, !id.hasPrefix("com.apple.") else { return }
        assignments[id] = place
    }
    public mutating func remember(_ entries: [AppEntry]) {
        let fresh = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var combined = Dictionary(remembered.map { ($0.id, AppEntry(id: $0.id, name: $0.name, isRunning: false)) }, uniquingKeysWith: { first, _ in first })
        combined.merge(fresh, uniquingKeysWith: { _, new in new })
        remembered = combined.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let unseen = entries.map(\.id).filter { !order.contains($0) }
        order.append(contentsOf: unseen)
    }
    public func hiddenBundles(reveal: Reveal, ownID: String, temporary: Set<String> = []) -> Set<String> {
        Set(assignments.compactMap { id, place in
            guard id != ownID, !id.hasPrefix("com.apple."), !temporary.contains(id), !reveal.includes(place) else { return nil }
            return id
        })
    }
    public mutating func move(_ id: String, before target: String?) {
        guard id != target else { return }
        order.removeAll { $0 == id }
        if let target, let index = order.firstIndex(of: target) { order.insert(id, at: index) }
        else { order.append(id) }
    }
    public func validated() -> Preferences {
        var p = self
        p.rehideDelay = p.rehideDelay.isFinite ? min(max(p.rehideDelay, 2), 60) : 8
        p.tintOpacity = p.tintOpacity.isFinite ? min(max(p.tintOpacity, 0.03), 0.6) : 0.14
        if p.tintHex.count != 6 || UInt(p.tintHex, radix: 16) == nil { p.tintHex = "146B60" }
        p.assignments = p.assignments.filter { !$0.key.isEmpty && !$0.key.hasPrefix("com.apple.") }
        var seen: Set<String> = []
        p.order = p.order.filter { seen.insert($0).inserted }
        return p
    }
}

public enum MenuBarIcon: String, Codable, CaseIterable, Identifiable, Sendable {
    case nook, dot, chevron, leaf, tiles
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// A successful hide must never strand the user without a reveal control.
public enum VisibilityCheck: Equatable, Sendable {
    case verified, unavailableControl, unavailableSnapshot
    case unexpectedVisibility(Set<String>), missingApps(Set<String>)

    public static func evaluate(controlReachable: Bool, snapshotAvailable: Bool,
                                visible: Set<String>, hidden: Set<String>, expected: Set<String>) -> VisibilityCheck {
        guard controlReachable else { return .unavailableControl }
        guard snapshotAvailable else { return .unavailableSnapshot }
        let exposed = visible.intersection(hidden)
        if !exposed.isEmpty { return .unexpectedVisibility(exposed) }
        let missing = expected.subtracting(visible)
        if !missing.isEmpty { return .missingApps(missing) }
        return .verified
    }
}

public enum BarShape: String, Codable, CaseIterable, Sendable {
    case full, rounded, split
    public var title: String { rawValue.capitalized }
}

/// Separates saved organisation from transient visibility. Unassigned apps stay visible.
public struct VisibilityPlan: Equatable, Sendable {
    public let hidden: Set<String>
    public let allowed: Set<String>
    public init(preferences: Preferences, runningBundles: Set<String>, reveal: Reveal, ownID: String, temporary: Set<String> = []) {
        hidden = preferences.hiddenBundles(reveal: reveal, ownID: ownID, temporary: temporary)
        allowed = runningBundles.subtracting(hidden).union([ownID])
    }
}
