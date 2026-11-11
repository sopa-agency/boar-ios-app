import XCTest

/// The whole app by the normal path, in the demo state: every screen reachable from the menu, each button, switch,
/// picker and menu a user can reach there, each sheet opened and closed. Destructive actions (clear, reset, erase,
/// delete) are opened and cancelled; downloads, imports and the system pickers aren't started.
final class SmokeUITests: BoarUITestCase {
    /// The sessions sidebar (Android's menu): one back from the chat on iPhone.
    private func openMenu() {
        let back = app.navigationBars.buttons["BackButton"].firstMatch
        if back.waitForExistence(timeout: 3) { back.tap() }
        XCTAssertTrue(text("Chats").waitForExistence(timeout: 5) || anything("Chats").exists, "the menu didn't open")
        assertRunning()
    }

    private func openMenuRow(_ english: String) {
        openMenu()
        tap(anything(english), "menu row \(english)")
    }

    // MARK: Chat

    func testChat() {
        launch()
        auditLabels("chat")
        // The answer style menu (the button left of the input).
        tap(button("Answer Style"), "Answer Style")
        XCTAssertTrue(anything("Succinct & Direct").waitForExistence(timeout: 5), "the style list didn't open")
        auditLabels("answer style")
        let quick = anything("Succinct & Direct")
        tap(quick, "Succinct & Direct")
        // A menu closes on the pick; a sheet may need closing.
        if anything("Thorough & Detailed").exists && anything("Thorough & Detailed").isHittable { closeSheet() }
        assertRunning()
        // Back to the default style.
        tap(button("Answer Style"), "Answer Style")
        tap(anything("Thorough & Detailed"), "Thorough & Detailed")
        if anything("Succinct & Direct").exists && anything("Succinct & Direct").isHittable { closeSheet() }

        // A question, typed and sent.
        let field = app.textFields[L("Ask BOAR")].firstMatch
        tap(field, "the question field")
        field.typeText("12 * 7")
        // The composer's Send, not the keyboard's send key (identifier "Send").
        tap(app.buttons.matching(NSPredicate(format: "label == %@ AND identifier == ''", L("Send"))).firstMatch, "Send")
        // The demo's model files are sparse placeholders, never loaded: BOAR says No Answer Model, and its button opens
        // Models (with a real model: the answer, 84).
        let answer = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label == %@", "84", L("No Answer Model"))).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 20), "no reply to 12 * 7\n\(app.debugDescription)")
        dismissKeyboard()
        auditLabels("chat with a reply")
        if text("No Answer Model").exists {
            tap(anything("Open Models"), "Open Models")
            XCTAssertTrue(app.navigationBars[L("Models")].waitForExistence(timeout: 5), "Open Models didn't open Models")
            openMenu()
        }
        // New Chat empties it again.
        tap(button("New Chat"), "New Chat")
        XCTAssertTrue(app.textFields[L("Ask BOAR")].waitForExistence(timeout: 5))
        auditLabels("new chat")
    }

    func testSavedChat() {
        launch()
        openMenu()
        auditLabels("menu")
        // The first demo chat.
        let firstChat = app.collectionViews.cells.matching(NSPredicate(format: "label != ''")).element(boundBy: 0)
        let row = app.collectionViews.firstMatch.cells.allElementsBoundByIndex.first { cell in
            cell.isHittable && cell.frame.minY > text("Chats").frame.maxY
        } ?? firstChat
        tap(row, "the first saved chat")
        XCTAssertTrue(app.textFields[L("Ask BOAR")].waitForExistence(timeout: 5), "the chat didn't open")
        dismissKeyboard()
        auditLabels("saved chat")
        // Its sources, if the demo answer has them: open the first and close it.
        let sources = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", L("Source") + " ")).firstMatch
        if sources.exists {
            tap(sources, "a source")
            auditLabels("source sheet")
            closeSheet()
        }
        // The mascot in the title opens it full screen; a tap closes it.
        let mascot = app.navigationBars.buttons["BOAR"].firstMatch
        if mascot.exists && mascot.isHittable {
            mascot.tap()
            assertRunning()
            app.tap()
            assertRunning()
        }
    }

    // MARK: Library

    func testModels() {
        launch()
        openMenuRow("Models")
        XCTAssertTrue(app.navigationBars[L("Models")].waitForExistence(timeout: 5), "Models didn't open")
        auditLabels("models")
        // The first model's details, and back.
        let details = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "GB")).firstMatch
        if details.exists {
            tap(details, "a model row")
            auditLabels("model detail")
            if !app.navigationBars[L("Models")].exists { goBack() }
        }
        assertRunning()
    }

    func testKnowledge() {
        launch()
        openMenuRow("Knowledge")
        XCTAssertTrue(app.navigationBars[L("Knowledge")].waitForExistence(timeout: 5), "Knowledge didn't open")
        auditLabels("knowledge")
        assertRunning()
    }

    func testLabs() {
        launch()
        openMenuRow("Boar Labs")
        let title = app.navigationBars[L("Boar Labs")]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Boar Labs didn't open")
        auditLabels("labs")
        // Every tile, top to bottom: an open lab pushes its page (audit it, come back); a classified one only counts
        // the tap.
        var tiles: [String] = []
        for _ in 0..<6 {
            for b in app.scrollViews.firstMatch.buttons.allElementsBoundByIndex where b.isHittable && !b.label.isEmpty {
                if !tiles.contains(b.label) { tiles.append(b.label) }
            }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertFalse(tiles.isEmpty, "no lab tiles\n\(app.debugDescription)")
        var pages = 0
        for label in tiles {
            let tile = app.scrollViews.firstMatch.buttons[label].firstMatch
            tap(tile, "lab tile \(label)")
            if !title.waitForExistence(timeout: 1.5) {
                pages += 1
                auditLabels("lab page \(label)")
                app.swipeUp()
                auditLabels("lab page \(label), lower")
                goBack()
                XCTAssertTrue(title.waitForExistence(timeout: 5), "didn't come back from \(label)")
            }
        }
        XCTAssertGreaterThan(pages, 0, "no lab page opened (tiles: \(tiles))")
    }

    // MARK: Settings

    func testSettings() {
        launch()
        openMenu()
        tap(button("Settings"), "Settings")
        XCTAssertTrue(app.navigationBars[L("Settings")].waitForExistence(timeout: 5), "Settings didn't open")
        auditLabels("settings")

        // Answers: the style list pushes, and back.
        tap(anything("Answer Style"), "Answer Style row")
        auditLabels("settings answer style")
        goBack()
        flipTwice("Deep Research")

        // Memory, display, privacy, voice.
        for name in ["Generate Chat Titles", "Ask Before Deleting a Chat", "Free Memory When I Leave BOAR", "Haptics"] {
            flipTwice(name)
        }
        // The theme menu: Campfire, then back to System.
        tap(anything("Theme"), "Theme")
        menuItem("Campfire").tap()
        assertRunning()
        tap(anything("Theme"), "Theme")
        menuItem("System").tap()
        assertRunning()
        auditLabels("settings after theme")

        // Advanced and everything under it.
        tap(anything("Advanced"), "Advanced")
        XCTAssertTrue(app.navigationBars[L("Advanced")].waitForExistence(timeout: 5))
        auditLabels("advanced")
        tap(anything("Answer Length"), "Answer Length")
        menuItem("Auto").tap()
        assertRunning()
        tap(anything("Engine"), "Engine")
        auditLabels("engine choice")
        goBack()
        flipTwice("Summarize Older Turns")
        // Built from "%@ & Storage" with the device's name, so it has no catalog key of its own.
        tap(anything(String(format: L("%@ & Storage"), "iPhone")), "iPhone & Storage")
        auditLabels("device info")
        goBack()
        let technical = reveal(toggle("Show Technical Details"), "Show Technical Details")
        let wasOn = technical.value as? String == "1"
        if !wasOn { flipOnce(technical) }
        flipTwice("Adaptive Routing")
        tap(anything("Engine Tweaks"), "Engine Tweaks")
        auditLabels("engine tweaks")
        goBack()
        tap(anything("Benchmark"), "Benchmark")
        auditLabels("benchmark")
        goBack()
        if !wasOn { flipOnce(reveal(toggle("Show Technical Details"), "Show Technical Details")) }
        flipTwice("Boar Labs")
        goBack()

        // About, to its end.
        tap(anything("About BOAR"), "About BOAR")
        auditLabels("about")
        app.swipeUp()
        app.swipeUp()
        auditLabels("about, end")
        goBack()

        // The destructive actions: each one asks first; cancel them all.
        for name in ["Clear Chat History", "Reset Settings", "Erase All Data"] {
            tap(button(name), name)
            XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3) || app.alerts.firstMatch.exists,
                          "\(name) didn't ask first")
            cancelDialog()
        }
        XCTAssertTrue(app.navigationBars[L("Settings")].exists, "a cancelled dialog left Settings")
    }

    /// An item of the menu on screen ("🔥 Campfire" for "Campfire").
    private func menuItem(_ english: String) -> XCUIElement {
        let item = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", L(english))).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3), "menu item \(english) not found\n\(app.debugDescription)")
        return item
    }

    private func flipOnce(_ s: XCUIElement) {
        tapSwitch(s)
        assertRunning()
    }

    /// A confirmation dialog's Cancel, or a tap outside it.
    private func cancelDialog() {
        let cancel = app.buttons[L("Cancel")].firstMatch
        if cancel.waitForExistence(timeout: 2) && cancel.isHittable {
            cancel.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        }
        assertRunning()
    }

    // MARK: Setup

    func testSetup() {
        launch(screen: "setup")
        tap(button("Get Your Library"), "Get Your Library")
        XCTAssertTrue(anything("Answer Model").waitForExistence(timeout: 5), "the model step didn't open")
        auditLabels("setup model")
        tap(button("Continue"), "Continue")
        XCTAssertTrue(anything("Library").waitForExistence(timeout: 5), "the library step didn't open")
        auditLabels("setup library")
        // Not the download: back to the start.
        tap(button("Back"), "Back")
        XCTAssertTrue(anything("Answer Model").waitForExistence(timeout: 5))
        tap(button("Back"), "Back")
        XCTAssertTrue(button("Get Your Library").waitForExistence(timeout: 5))
    }
}
