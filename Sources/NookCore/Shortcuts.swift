import Foundation

public enum ShortcutAction: Int, CaseIterable, Identifiable, Sendable {
    case toggle = 1, search, showAll
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .toggle: return "Show or hide apps"
        case .search: return "Search apps"
        case .showAll: return "Show all apps"
        }
    }
}

public struct KeyModifiers: OptionSet, Codable, Equatable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let command = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let control = Self(rawValue: 1 << 2)
    public static let shift = Self(rawValue: 1 << 3)
    public static let allowed: Self = [.command, .option, .control, .shift]
}

public struct KeyChord: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: KeyModifiers
    public init(keyCode: UInt32, modifiers: KeyModifiers) {
        self.keyCode = keyCode; self.modifiers = modifiers
    }
    public var isValid: Bool {
        keyCode <= 126 && modifiers.isSubset(of: .allowed)
            && !modifiers.intersection([.command, .option, .control]).isEmpty
            && ![UInt32(54), 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }
}

public struct ShortcutBindings: Codable, Equatable, Sendable {
    public var toggle = KeyChord(keyCode: 45, modifiers: [.control, .option])
    public var search = KeyChord(keyCode: 49, modifiers: [.control, .option])
    public var showAll = KeyChord(keyCode: 45, modifiers: [.control, .option, .shift])
    public init() {}
    public subscript(action: ShortcutAction) -> KeyChord {
        get {
            switch action { case .toggle: return toggle; case .search: return search; case .showAll: return showAll }
        }
        set {
            switch action { case .toggle: toggle = newValue; case .search: search = newValue; case .showAll: showAll = newValue }
        }
    }
    public func conflict(for chord: KeyChord, excluding action: ShortcutAction) -> ShortcutAction? {
        ShortcutAction.allCases.first { $0 != action && self[$0] == chord }
    }
    public func validated() -> Self {
        var result = self
        for action in ShortcutAction.allCases where !result[action].isValid { result[action] = Self()[action] }
        return result
    }
}
