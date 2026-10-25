import Foundation
import Testing
@testable import NookCore

@Test func olderPreferencesKeepAssignmentsAndSkipRepeatedSetup() throws {
    let data = Data(#"{"remembered":[{"id":"org.sample.App","name":"App","isRunning":true}],"assignments":{"org.sample.App":"quiet"}}"#.utf8)
    let loaded = try JSONDecoder().decode(Preferences.self, from: data)
    #expect(loaded.setupCompleted)
    #expect(loaded.place(for: "org.sample.App") == .quiet)
    #expect(loaded.shortcuts == ShortcutBindings())
    #expect(loaded.pause == nil)
    #expect(!Preferences().setupCompleted)
}

@Test func emptyNamesHaveAnIdentityAndRememberedDuplicatesAreRemoved() {
    #expect(AppEntry(id: "org.sample.Reader", name: " \n ").displayName == "Reader")
    var p = Preferences()
    p.remember([AppEntry(id: "a", name: ""), AppEntry(id: "a", name: "App")])
    #expect(p.order == ["a"])
    p.remembered.append(AppEntry(id: "a", name: "Duplicate"))
    #expect(p.validated().remembered.count == 1)
}

@Test func undoRestoresOneAppWithoutRevertingOtherSettingsOrNewApps() {
    var p = Preferences()
    p.remember([AppEntry(id: "a", name: "A"), AppEntry(id: "b", name: "B")])
    p.assign("a", to: .quiet, ownID: "nook")
    let before = p.organisationState(for: "a")
    p.forget("a")
    let forgotten = p.organisationState(for: "a")
    p.tintHex = "123456"
    p.remember([AppEntry(id: "c", name: "New app")])
    p.restore(before)
    #expect(p.place(for: "a") == .quiet)
    #expect(p.order == ["a", "b", "c"])
    #expect(p.remembered.contains { $0.id == "c" })
    #expect(p.tintHex == "123456")
    p.restore(forgotten)
    #expect(!p.remembered.contains { $0.id == "a" })
    #expect(p.order == ["b", "c"])
}

@Test func undoReassignmentRestoresUnassignedStateAndOrder() {
    var p = Preferences()
    p.remember([AppEntry(id: "a", name: "A"), AppEntry(id: "b", name: "B")])
    let before = p.organisationState(for: "b")
    p.assign("b", to: .tucked, ownID: "nook"); p.move("b", before: "a")
    p.restore(before)
    #expect(p.assignments["b"] == nil)
    #expect(p.order == ["a", "b"])
}

@Test func pauseExpiryAndIndefinitePauseRoundTrip() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    #expect(HidingPause().isActive(at: now))
    let pause = HidingPause(until: now.addingTimeInterval(300))
    #expect(pause.isActive(at: now))
    #expect(!pause.isActive(at: now.addingTimeInterval(300)))
    var p = Preferences(); p.pause = pause; p.setupCompleted = true
    p.shortcuts.search = KeyChord(keyCode: 1, modifiers: [.command, .shift])
    #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p)) == p)
}

@Test func invalidGlobalShortcutsFallBackAndConflictsIdentifyTheOtherAction() {
    var bindings = ShortcutBindings()
    #expect(bindings.conflict(for: bindings.toggle, excluding: .search) == .toggle)
    bindings.search = KeyChord(keyCode: 0, modifiers: [.shift])
    bindings.showAll = KeyChord(keyCode: 999, modifiers: [.control])
    let clean = bindings.validated()
    #expect(clean.search == ShortcutBindings().search)
    #expect(clean.showAll == ShortcutBindings().showAll)
    #expect(!KeyChord(keyCode: 55, modifiers: [.command]).isValid)
    #expect(KeyChord(keyCode: 0, modifiers: [.command, .shift]).isValid)
}

@Test func unreasonableImportedPauseDeadlinesRequireExplicitResume() {
    var p = Preferences()
    p.pause = HidingPause(until: Date(timeIntervalSinceReferenceDate: 1e308))
    #expect(p.validated().pause == HidingPause())
}

@Test func splitAppearanceUsesTheActualNotchAndStaysInsideTheBar() {
    let bounds = CGRect(x: 0, y: 0, width: 1200, height: 38)
    let notch = CGRect(x: 530, y: 0, width: 140, height: 38)
    let pieces = MenuBarGeometry.segments(in: bounds, shape: .split, notch: notch)
    #expect(pieces.count == 2)
    #expect(pieces[0].maxX < notch.minX)
    #expect(pieces[1].minX > notch.maxX)
    #expect(pieces.allSatisfy { bounds.contains($0) })
    #expect(MenuBarGeometry.segments(in: bounds, shape: .full) == [bounds])
    #expect(MenuBarGeometry.segments(in: .zero, shape: .split).isEmpty)
    #expect(MenuBarGeometry.segments(in: CGRect(x: 0, y: 0, width: 10, height: 3), shape: .split).isEmpty)
}
