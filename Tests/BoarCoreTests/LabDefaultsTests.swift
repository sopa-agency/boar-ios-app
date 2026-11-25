import Testing
@testable import BoarCore

/// android LabDefaultsTest (the parts that don't read Android's source tree; the source guards are in
/// `PluginsWiringTests`). Android's list is kept as it is; `startsOffHere` is iOS's one difference.
struct LabDefaultsTests {
    @Test func theDefaultOnSetIsAdamsListWithoutTheAlphaLabsStillPending() {
        #expect(LabDefaults.on == ["pulse", "image", "printer", "calc", "distance", "facts", "cohazard", "canvas"])
        // Polyglot starts off (adam, Nov 11) and is deprecated since Nov 23.
        #expect(!LabDefaults.on.contains("polyglot") && LabDefaults.deprecated == ["polyglot"])
        #expect(LabDefaults.pendingAlpha == ["compass", "lunar", "guard"])
        #expect(LabDefaults.on.isDisjoint(with: LabDefaults.pendingAlpha))
    }

    @Test func theLabsAdamKeepsOffStartOff() {
        for id in ["bmoe", "colibri", "dailyQuiz", "sanctuary", "signboard", "polyglot"] {
            #expect(!LabDefaults.switchOf(id, stored: nil), "\(id)")
        }
    }

    /// iOS: Designer is on Android's list but starts off here (Image Playground needs Apple Intelligence).
    @Test func designerStartsOffOnIOSAndFollowsTheUsersChoice() {
        #expect(LabDefaults.on.contains("image") && LabDefaults.startsOffHere == ["image"])
        #expect(LabDefaults.startsOn == ["pulse", "printer", "calc", "distance", "facts", "cohazard", "canvas"])
        #expect(!LabDefaults.switchOf("image", stored: nil))
        #expect(LabDefaults.switchOf("image", stored: true))
    }

    @Test func aFreshInstallGetsExactlyTheDefaultSet() {
        let ids = ["pulse", "image", "printer", "calc", "distance", "facts", "cohazard", "compass", "lunar", "guard", "polyglot", "dailyQuiz"]
        #expect(Set(ids.filter { LabDefaults.switchOf($0, stored: nil) }) == ["pulse", "printer", "calc", "distance", "facts", "cohazard"])
    }

    @Test func theUsersOwnSwitchWinsOverTheDefault() {
        #expect(!LabDefaults.switchOf("calc", stored: false))
        #expect(LabDefaults.switchOf("bmoe", stored: true))
        #expect(LabDefaults.switchOf("calc", stored: nil))
    }

    @Test func theUpdateNoteNamesTheDefaultOnLabsTheUserNeverSwitched() {
        let ids = ["pulse", "calc", "facts", "bmoe", "distance", "compass", "printer"]
        let stored: [String: Bool] = ["calc": false, "facts": true, "bmoe": true]
        // Android's list has `image` where this has `distance`: Designer isn't one of iOS's default-on plugins.
        #expect(LabDefaults.turnedOnByUpdate(ids: ids) { stored[$0] } == ["pulse", "distance", "printer"])
        #expect(LabDefaults.turnedOnByUpdate(ids: ["image", "pulse"]) { stored[$0] } == ["pulse"])
    }

    @Test func anUpdateThatChangesNothingNamesNoLab() {
        #expect(LabDefaults.turnedOnByUpdate(ids: LabDefaults.on.sorted()) { _ in false }.isEmpty)
    }

    @Test func aLabLeftOnCountsOnlyWhilePluginsIsOn() {
        #expect(LabDefaults.userChoseOn(labsOn: true, stored: [nil, true, false]))
        #expect(!LabDefaults.userChoseOn(labsOn: false, stored: [true]))
        #expect(!LabDefaults.userChoseOn(labsOn: true, stored: [nil, false]))
    }

    @Test func onlyProManagesLabs() {
        #expect(!LabDefaults.managementShown(.simple))
        #expect(!LabDefaults.managementShown(.explorer))
        #expect(LabDefaults.managementShown(.pro))
    }
}
