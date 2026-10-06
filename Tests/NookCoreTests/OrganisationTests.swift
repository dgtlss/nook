import Testing
import Foundation
@testable import NookCore

private let ownID = "dev.nathanlanger.Nook"

@Test func unassignedAppsStayVisible() {
    let p = Preferences()
    let plan = VisibilityPlan(preferences: p, runningBundles: ["org.sample.A", ownID], reveal: .tucked, ownID: ownID)
    #expect(plan.hidden.isEmpty)
    #expect(plan.allowed == ["org.sample.A", ownID])
}

@Test func threeSectionsRevealIndependently() {
    var p = Preferences()
    p.assign("org.sample.A", to: .tucked, ownID: ownID)
    p.assign("org.sample.B", to: .quiet, ownID: ownID)
    #expect(p.hiddenBundles(reveal: .tucked, ownID: ownID) == ["org.sample.A", "org.sample.B"])
    #expect(p.hiddenBundles(reveal: .peek, ownID: ownID) == ["org.sample.B"])
    #expect(p.hiddenBundles(reveal: .everything, ownID: ownID).isEmpty)
}

@Test func protectNookAndNativeApps() {
    var p = Preferences()
    for id in [ownID, "com.apple.controlcenter", "com.apple.MenuBarAgent", ""] {
        p.assign(id, to: .quiet, ownID: ownID)
    }
    #expect(p.assignments.isEmpty)
    p.assignments[ownID] = .quiet
    p.assignments["com.apple.controlcenter"] = .quiet
    #expect(p.hiddenBundles(reveal: .tucked, ownID: ownID).isEmpty)
}

@Test func revealOneAppWithoutRevealingItsNeighbours() {
    var p = Preferences()
    p.assignments = ["org.sample.A": .tucked, "org.sample.B": .tucked, "org.sample.C": .quiet]
    let plan = VisibilityPlan(preferences: p, runningBundles: ["org.sample.A", "org.sample.B", "org.sample.C"], reveal: .tucked, ownID: ownID, temporary: ["org.sample.A"])
    #expect(plan.hidden == ["org.sample.B", "org.sample.C"])
    #expect(plan.allowed == [ownID, "org.sample.A"])
    #expect(p.place(for: "org.sample.A") == .tucked)
}

@Test func newAppsRemainAllowedWhileHidden() {
    var p = Preferences()
    p.assignments = ["org.sample.A": .tucked]
    let plan = VisibilityPlan(preferences: p, runningBundles: ["org.sample.A", "org.newlyLaunched.B", "com.apple.controlcenter"], reveal: .tucked, ownID: ownID)
    #expect(plan.allowed.contains("org.newlyLaunched.B"))
    #expect(plan.allowed.contains("com.apple.controlcenter"))
}

@Test func discoveryDoesNotForgetHiddenOrAbsentApps() {
    var p = Preferences()
    p.remember([AppEntry(id: "org.sample.A", name: "A"), AppEntry(id: "org.sample.B", name: "B")])
    p.assignments["org.sample.A"] = .quiet
    p.remember([AppEntry(id: "org.sample.B", name: "B"), AppEntry(id: "org.sample.C", name: "C")])
    #expect(p.remembered.count == 3)
    #expect(p.remembered.first { $0.id == "org.sample.A" }?.isRunning == false)
    #expect(p.place(for: "org.sample.A") == .quiet)
    #expect(p.order.count == 3)
}

@Test func duplicateDiscoveryDoesNotDuplicateCards() {
    var p = Preferences()
    p.remember([AppEntry(id: "org.sample.A", name: "A"), AppEntry(id: "org.sample.A", name: "A")])
    #expect(p.remembered.count == 1)
    #expect(p.validated().order == ["org.sample.A"])
}

@Test func reorderBeforeTargetAndAppend() {
    var p = Preferences(); p.order = ["a", "b", "c"]
    p.move("c", before: "a")
    #expect(p.order == ["c", "a", "b"])
    p.move("a", before: nil)
    #expect(p.order == ["c", "b", "a"])
    p.move("b", before: "b")
    #expect(p.order == ["c", "b", "a"])
}

@Test func settingsRoundTripPreservesChoices() throws {
    var p = Preferences()
    p.assignments = ["org.sample.A": .quiet]; p.order = ["org.sample.A"]
    p.showOnHover = true; p.useShelf = true; p.shape = .split; p.tintHex = "FF8800"
    #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p)) == p)
}

@Test func invalidImportedSettingsAreBounded() {
    var p = Preferences()
    p.rehideDelay = -30; p.tintOpacity = 3; p.tintHex = "not a colour"
    p.order = ["a", "a", "b"]; p.assignments = ["": .quiet, "com.apple.MenuBarAgent": .quiet, "org.sample.A": .tucked]
    let clean = p.validated()
    #expect(clean.rehideDelay == 2)
    #expect(clean.tintOpacity == 0.6)
    #expect(clean.tintHex == "146B60")
    #expect(clean.order == ["a", "b"])
    #expect(clean.assignments == ["org.sample.A": .tucked])
}

@Test func nonFiniteSettingsUseDefaults() {
    var p = Preferences(); p.rehideDelay = .nan; p.tintOpacity = .infinity
    #expect(p.validated().rehideDelay == 8)
    #expect(p.validated().tintOpacity == 0.14)
}

@Test func restoringAllAllowsEveryRunningApp() {
    var p = Preferences(); p.assignments = ["org.sample.A": .quiet]
    let plan = VisibilityPlan(preferences: p, runningBundles: ["org.sample.A", "org.sample.B"], reveal: .everything, ownID: ownID)
    #expect(plan.hidden.isEmpty)
    #expect(plan.allowed == [ownID, "org.sample.A", "org.sample.B"])
}

@Test func olderSettingsKeepOrganisationWhenIconIsAdded() throws {
    var original = Preferences()
    original.assignments = ["org.sample.A": .tucked, "org.sample.B": .quiet]
    original.order = ["org.sample.B", "org.sample.A"]
    original.rehide = false; original.rehideDelay = 17
    original.tintEnabled = true; original.tintHex = "FF8800"
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    json.removeValue(forKey: "menuBarIcon")
    let loaded = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(loaded == original)
    #expect(loaded.menuBarIcon == .nook)
}

@Test func iconChoicesPersistAndUnknownChoicesFallBack() throws {
    for choice in MenuBarIcon.allCases {
        var p = Preferences(); p.menuBarIcon = choice
        #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p)).menuBarIcon == choice)
    }
    let future = Data(#"{"menuBarIcon":"future-icon","assignments":{"org.sample.A":"quiet"}}"#.utf8)
    let loaded = try JSONDecoder().decode(Preferences.self, from: future)
    #expect(loaded.menuBarIcon == .nook)
    #expect(loaded.place(for: "org.sample.A") == .quiet)
}

@Test func losingRevealControlInvalidatesAnOtherwiseSuccessfulHide() {
    let result = VisibilityCheck.evaluate(controlReachable: false, snapshotAvailable: true,
        visible: ["org.sample.A"], hidden: ["org.sample.B"], expected: ["org.sample.A"])
    #expect(result == .unavailableControl)
}

@Test func hostMustRetainNookEvenWhenAppKitReportsVisible() {
    let visible: Set<String> = ["org.sample.A"]
    #expect(VisibilityCheck.evaluate(controlReachable: true, snapshotAvailable: true,
        visible: visible, hidden: ["org.sample.B"], expected: visible.union([ownID])) == .missingApps([ownID]))
}

@Test func verificationRequiresBothVisibilityAndAUsableSnapshot() {
    #expect(VisibilityCheck.evaluate(controlReachable: true, snapshotAvailable: false,
        visible: [], hidden: ["b"], expected: []) == .unavailableSnapshot)
    #expect(VisibilityCheck.evaluate(controlReachable: true, snapshotAvailable: true,
        visible: ["a", "b"], hidden: ["b"], expected: ["a"]) == .unexpectedVisibility(["b"]))
    #expect(VisibilityCheck.evaluate(controlReachable: true, snapshotAvailable: true,
        visible: [], hidden: ["b"], expected: ["a"]) == .missingApps(["a"]))
    #expect(VisibilityCheck.evaluate(controlReachable: true, snapshotAvailable: true,
        visible: ["a"], hidden: ["b"], expected: ["a"]) == .verified)
}
