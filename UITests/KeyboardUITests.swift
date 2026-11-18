import XCTest

/// The keyboard on a new chat: it opens ready to type, and a tap beside the ideas or a drag down puts it away. With the
/// keyboard up the mascot steps aside and the ideas fit the screen, so there used to be nothing to drag or tap (BOAR-57).
final class KeyboardUITests: BoarUITestCase {
    func testTapBesideTheIdeasClosesTheKeyboard() {
        launch()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "a new chat didn't open with the keyboard")
        // The empty space over the ideas (they rest on the composer while typing).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertTrue(keyboardGone(), "a tap beside the ideas left the keyboard up")
        // Still the empty chat: the tap didn't land on an idea (asking one closes the keyboard too).
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "promptIdea").firstMatch.exists,
                      "the tap asked an idea instead of landing beside them")
    }

    func testDragDownClosesTheKeyboard() {
        launch()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "a new chat didn't open with the keyboard")
        // From the empty space down through the keyboard, as a thumb puts it away.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(keyboardGone(), "a drag down left the keyboard up")
    }

    /// With the keyboard up, an idea still answers its own gestures: a long press puts it in the field (the keyboard
    /// stays), a tap asks it.
    func testIdeasStillWorkWhileTyping() {
        launch()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "a new chat didn't open with the keyboard")
        let field = app.textFields[L("Ask BOAR")].firstMatch
        let idea = app.descendants(matching: .any).matching(identifier: "promptIdea").firstMatch
        XCTAssertTrue(idea.waitForExistence(timeout: 5), "no ideas on the new chat")
        idea.press(forDuration: 1.0)
        let filled = expectation(for: NSPredicate(format: "value != %@ AND value != ''", L("Ask BOAR")), evaluatedWith: field)
        XCTAssertEqual(XCTWaiter.wait(for: [filled], timeout: 3), .completed, "a long press didn't put the idea in the field")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "a long press put the keyboard away")
        // A tap asks it: the empty chat gives way to the conversation, and the keyboard closes as on send.
        let other = app.descendants(matching: .any).matching(identifier: "promptIdea").element(boundBy: 1)
        tap(other, "an idea")
        XCTAssertTrue(keyboardGone(), "asking an idea left the keyboard up")
        let asked = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: idea)
        XCTAssertEqual(XCTWaiter.wait(for: [asked], timeout: 5), .completed, "a tap on an idea didn't ask it")
    }

    /// The keyboard is down (it animates away).
    private func keyboardGone() -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        return XCTWaiter.wait(for: [gone], timeout: 3) == .completed
    }
}
