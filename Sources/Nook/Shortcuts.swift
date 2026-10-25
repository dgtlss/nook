import AppKit
import Carbon
import SwiftUI
import NookCore

extension KeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var value: Self = []
        if flags.contains(.command) { value.insert(.command) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.control) { value.insert(.control) }
        if flags.contains(.shift) { value.insert(.shift) }
        self = value
    }
    var carbon: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }
}

extension KeyChord {
    var display: String {
        var prefix = ""
        if modifiers.contains(.control) { prefix += "⌃" }
        if modifiers.contains(.option) { prefix += "⌥" }
        if modifiers.contains(.shift) { prefix += "⇧" }
        if modifiers.contains(.command) { prefix += "⌘" }
        let special: [UInt32: String] = [36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
            76: "Enter", 115: "Home", 116: "Page Up", 117: "Delete", 119: "End", 121: "Page Down",
            123: "←", 124: "→", 125: "↓", 126: "↑"]
        if let key = special[keyCode] { return prefix + key }
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
            if let bytes = CFDataGetBytePtr(data) {
                let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
                var dead: UInt32 = 0, length = 0
                var characters = [UniChar](repeating: 0, count: 8)
                let result = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead,
                    characters.count, &length, &characters)
                if result == noErr, length > 0 {
                    return prefix + String(utf16CodeUnits: characters, count: length).uppercased()
                }
            }
        }
        return prefix + "Key \(keyCode)"
    }
    func matches(_ event: NSEvent) -> Bool {
        keyCode == UInt32(event.keyCode) && modifiers == KeyModifiers(event.modifierFlags)
    }
}

@MainActor final class ShortcutController {
    var action: ((ShortcutAction) -> Void)?
    private(set) var issues: [ShortcutAction: String] = [:]
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var bindings: ShortcutBindings?
    private var enabled = false

    func configure(enabled: Bool, bindings: ShortcutBindings) {
        guard self.enabled != enabled || self.bindings != bindings else { return }
        stop(); self.enabled = enabled; self.bindings = bindings
        guard enabled else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetEventDispatcherTarget(), { _, event, data in
            guard let event, let data else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, let action = ShortcutAction(rawValue: Int(id.id)) else { return result }
            MainActor.assumeIsolated {
                Unmanaged<ShortcutController>.fromOpaque(data).takeUnretainedValue().action?(action)
            }
            return noErr
        }, 1, &spec, context, &handler)
        guard installed == noErr else {
            for action in ShortcutAction.allCases { issues[action] = "macOS couldn’t enable this shortcut (\(installed))." }
            return
        }
        var registered: [KeyChord] = []
        for action in ShortcutAction.allCases {
            let chord = bindings[action]
            guard chord.isValid else { issues[action] = "Include Command, Control or Option."; continue }
            guard !registered.contains(chord) else { issues[action] = "This shortcut is already assigned to another Nook action."; continue }
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(chord.keyCode, chord.modifiers.carbon,
                EventHotKeyID(signature: 0x4E4F4F4B, id: UInt32(action.rawValue)), GetEventDispatcherTarget(), 0, &ref)
            if result == noErr, let ref { refs.append(ref); registered.append(chord) }
            else { issues[action] = "\(chord.display) is unavailable. Another app or macOS may be using it (\(result))." }
        }
    }
    func stop() {
        refs.forEach { UnregisterEventHotKey($0) }; refs = []
        if let handler { RemoveEventHandler(handler) }; handler = nil
        enabled = false; bindings = nil; issues = [:]
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var model: NookModel
    let action: ShortcutAction

    func makeNSView(context: Context) -> RecorderButton { RecorderButton() }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.title = model.recordingShortcut == action ? "Press shortcut…" : model.preferences.shortcuts[action].display
        button.setAccessibilityLabel("\(action.title) shortcut")
        button.setAccessibilityHelp("Click to record. Include Command, Control or Option. Escape cancels.")
        button.startRecording = { model.shortcutValidationIssues[action] = nil; model.recordingShortcut = action }
        button.finishRecording = { chord in
            model.recordingShortcut = nil
            if let chord { model.setShortcut(chord, for: action) }
        }
        button.recording = model.recordingShortcut == action
        button.isEnabled = model.preferences.hotkeyEnabled
    }
}

final class RecorderButton: NSButton {
    var startRecording: (() -> Void)?
    var finishRecording: ((KeyChord?) -> Void)?
    var recording = false
    override var acceptsFirstResponder: Bool { true }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded; setButtonType(.momentaryPushIn)
        font = .systemFont(ofSize: 13, weight: .medium)
        target = self; action = #selector(record)
    }
    required init?(coder: NSCoder) { nil }
    @objc private func record() {
        window?.makeFirstResponder(self); startRecording?()
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { finishRecording?(nil); return }
        let chord = KeyChord(keyCode: UInt32(event.keyCode), modifiers: KeyModifiers(event.modifierFlags))
        if chord.isValid { finishRecording?(chord) }
        else { title = "Use ⌘, ⌃ or ⌥"; NSAccessibility.post(element: self, notification: .valueChanged) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event); return true
    }
    override func resignFirstResponder() -> Bool {
        if recording { finishRecording?(nil) }
        return super.resignFirstResponder()
    }
}
