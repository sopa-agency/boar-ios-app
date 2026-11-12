import XCTest

/// Boar Avatars by the normal path: Boarverse on in Advanced, the grid from Settings, an avatar equipped there and back
/// to BOAR's own from the Display row; Boarverse off again at the end (it's stored outside the demo's files).
final class AvatarsUITests: BoarUITestCase {
    func testSwitchGridEquip() {
        // Cosmo unlocked on top of what the first open gives (tactical, and stealth and hacker in a debug build).
        launch(["-uiVault", #"{"facts":{"answers":1},"unlocked":{"tactical":1762819200000,"cosmo":1762819200000}}"#])
        let back = app.navigationBars.buttons["BackButton"].firstMatch
        if back.waitForExistence(timeout: 3) { back.tap() }
        tap(button("Settings"), "Settings")
        XCTAssertTrue(app.navigationBars[L("Settings")].waitForExistence(timeout: 5), "Settings didn't open")

        // Boarverse, at the bottom of Advanced.
        tap(anything("Advanced"), "Advanced")
        let boarverse = reveal(app.switches["settings.boarverse"].firstMatch, "Boarverse")
        if boarverse.value as? String != "1" { tapSwitch(boarverse) }
        XCTAssertTrue(waitValue(boarverse) { $0 == "1" }, "Boarverse didn't turn on")
        goBack()

        // The grid: the count, then Cosmo equipped.
        tap(app.buttons["settings.avatars"].firstMatch, "Open Boar Avatars")
        XCTAssertTrue(app.navigationBars[L("Boar Avatars")].waitForExistence(timeout: 5), "Boar Avatars didn't open")
        // How many the demo's first open adds (packs, models) isn't this test's business: "N of 40 avatars unlocked".
        let count = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS ' 40 ' AND label CONTAINS[c] 'avatar'")).firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 3), "no avatar count\n\(app.debugDescription)")
        auditLabels("boar avatars")
        tap(app.buttons["vault.avatar.cosmo"].firstMatch, "Cosmo Boar")
        okIconAlert()
        XCTAssertTrue(app.buttons["vault.avatar.cosmo"].firstMatch.isSelected, "Cosmo isn't equipped")
        XCTAssertTrue(app.buttons["vault.avatar.cosmo"].label.contains(L("Equipped")), "Cosmo doesn't say Equipped")
        // A locked one has no button.
        XCTAssertFalse(app.buttons["vault.avatar.elder"].exists, "a locked avatar can be equipped")
        goBack()

        // Display's row shows it picked; BOAR's own again.
        let cosmo = reveal(app.buttons["vault.pick.cosmo"].firstMatch, "Cosmo in the avatar row")
        XCTAssertTrue(cosmo.isSelected, "the row doesn't show Cosmo")
        tap(app.buttons["vault.pick.boar"].firstMatch, "BOAR in the avatar row")
        okIconAlert()
        XCTAssertTrue(app.buttons["vault.pick.boar"].firstMatch.isSelected, "BOAR's own isn't picked")
        auditLabels("settings with avatars")

        // Off again: the avatar section goes away.
        tap(anything("Advanced"), "Advanced")
        let off = reveal(app.switches["settings.boarverse"].firstMatch, "Boarverse")
        tapSwitch(off)
        XCTAssertTrue(waitValue(off) { $0 == "0" }, "Boarverse didn't turn off")
        goBack()
        XCTAssertFalse(app.buttons["settings.avatars"].exists, "Boar Avatars still in Settings with Boarverse off")
    }

    /// A build with BOAR_LAUNCHER_ICONS switches the app icon at Equip, and iOS says so in an alert of its own: OK it
    /// (logged, so a run with the icons shows the switch happened). Nothing to do in a build without them.
    private func okIconAlert() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let ok = springboard.alerts.buttons.firstMatch
        guard ok.waitForExistence(timeout: 4) else { print("app icon alert: none"); return }
        print("app icon alert: \(springboard.alerts.firstMatch.label)")
        ok.tap()
    }
}
