import Testing
@testable import BoarCore

/// android PluginReachTest (validator Q-B1): an off plugin stays one tap away, and Cohazard can't be lost with one tap.
/// The first Android test reads LabsScreen.kt for `pageSwitchShown`; here `PluginsWiringTests` reads the Swift source.
struct PluginReachTests {
    @Test func turningCohazardOffAsksFirstTurningItOnOrAnyOtherPluginOffDoesNot() {
        #expect(PluginReach.asksBeforeOff("cohazard", turningOn: false))
        #expect(!PluginReach.asksBeforeOff("cohazard", turningOn: true))
        #expect(!PluginReach.asksBeforeOff("calc", turningOn: false))
    }

    @Test func aSafetyPluginGoesOffOnlyOnceTheQuestionWasAnswered() {
        #expect(!PluginReach.allowsSet("cohazard", on: false, confirmed: false))
        #expect(PluginReach.allowsSet("cohazard", on: false, confirmed: true))
        #expect(PluginReach.allowsSet("cohazard", on: true, confirmed: false))
        #expect(PluginReach.allowsSet("calc", on: false, confirmed: false))
    }

    @Test func aPluginSwitchedOffFromItsPageIsListedAsOffAndStaysReachableWithNothingOn() {
        let ids = ["calc", "facts", "cohazard", "pulse"]
        var off = Set<String>()
        var on = ["calc": true, "facts": false, "cohazard": true, "pulse": false]
        // calc off from its page: listed; facts was off by default, not from a page: not listed.
        on["calc"] = false; off = PluginReach.offFromPageAfter(off, id: "calc", on: false, fromPage: true)
        #expect(PluginReach.offListed(ids, enabled: { on[$0]! }, offFromPage: off) == ["calc"])
        // Cohazard off (after the question): listed whatever the path.
        on["cohazard"] = false; off = PluginReach.offFromPageAfter(off, id: "cohazard", on: false, fromPage: false)
        #expect(PluginReach.offListed(ids, enabled: { on[$0]! }, offFromPage: off) == ["calc", "cohazard"])
        // Nothing on: the header icon still shows, so the off ones can be found.
        #expect(PluginReach.headerIconShown(activeIds: [], offListed: PluginReach.offListed(ids, enabled: { on[$0]! }, offFromPage: off)))
        #expect(!PluginReach.headerIconShown(activeIds: [], offListed: []))
        // Back on: out of the Off section.
        on["calc"] = true; off = PluginReach.offFromPageAfter(off, id: "calc", on: true, fromPage: true)
        #expect(PluginReach.offListed(ids, enabled: { on[$0]! }, offFromPage: off) == ["cohazard"])
        #expect(PluginReach.offFromPageAfter(["calc"], id: "calc", on: true, fromPage: false).isEmpty)
    }
}
