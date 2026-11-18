import XCTest

/// Deleting a chat from the menu (BOAR-58): a swipe's Delete removes it at once, with "Ask Before Deleting a Chat" on
/// (the default); the context menu's Delete still asks first.
final class ChatDeleteUITests: BoarUITestCase {
    private let first = "Why do we have seasons on Earth?"

    func testSwipeDeletesWithoutAsking() {
        launch()
        openChats()
        let before = chatTitles()
        let row = app.collectionViews.firstMatch.cells.containing(.staticText, identifier: first).firstMatch
        row.swipeLeft()
        tap(app.buttons[L("Delete")].firstMatch, "the swipe's Delete")
        XCTAssertTrue(gone(first), "the chat is still listed after the swipe's Delete")
        XCTAssertFalse(app.staticTexts[L("Delete this chat?")].exists, "a dialog after the swipe's Delete")
        XCTAssertEqual(chatTitles(), before.filter { !$0.hasPrefix(first) }, "other chats changed")
    }

    func testContextMenuDeleteAsksFirst() {
        launch()
        openChats()
        let before = chatTitles()
        app.collectionViews.firstMatch.cells.containing(.staticText, identifier: first).firstMatch.press(forDuration: 1.2)
        tap(app.buttons[L("Delete")].firstMatch, "the context menu's Delete")
        XCTAssertTrue(app.staticTexts[L("Delete this chat?")].firstMatch.waitForExistence(timeout: 3), "no dialog before deleting")
        XCTAssertEqual(chatTitles(), before, "a chat left the list before the dialog's answer")
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@", L("Delete"))).allElementsBoundByIndex.last!
        confirm.tap()
        XCTAssertTrue(gone(first), "the chat is still listed after Delete")
        XCTAssertEqual(chatTitles(), before.filter { !$0.hasPrefix(first) }, "other chats changed")
    }

    // MARK: Helpers

    private func openChats() {
        let back = app.navigationBars.buttons["BackButton"].firstMatch
        if back.waitForExistence(timeout: 3) { back.tap() }
        XCTAssertTrue(app.staticTexts[first].waitForExistence(timeout: 5), "the demo chat isn't in the menu")
    }

    /// The chats listed under Chats, by title.
    private func chatTitles() -> [String] {
        let header = text("Chats").frame.maxY
        return app.collectionViews.firstMatch.cells.allElementsBoundByIndex
            .filter { $0.frame.minY > header && $0.staticTexts.count >= 2 }
            .map { $0.staticTexts.firstMatch.label }
    }

    private func gone(_ title: String) -> Bool {
        let removed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts[title].firstMatch)
        return XCTWaiter.wait(for: [removed], timeout: 3) == .completed
    }
}
