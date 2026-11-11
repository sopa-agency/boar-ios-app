import Foundation
import XCTest

/// The smoke test's base: launches the DEBUG app in its demo state (`-uiDemo`: demo chats, no model, its own files and
/// settings) in the language from `BOAR_UI_LANG` (en or pt; pass it as `TEST_RUNNER_BOAR_UI_LANG=pt` to xcodebuild),
/// finds controls by their English label (looked up in the String Catalog for Portuguese), and audits every screen it
/// visits: the app still runs, and no visible button lacks a VoiceOver label.
@MainActor
class BoarUITestCase: XCTestCase {
    var app: XCUIApplication!
    /// Buttons without a usable label, as "screen: description", collected over the whole test.
    private var unlabelled: [String] = []

    static let language = ProcessInfo.processInfo.environment["BOAR_UI_LANG"] ?? "en"

    /// English → Portuguese from App/Resources/Localizable.xcstrings (found from this file, as the engine tests find
    /// their fixtures); empty in English.
    static let portuguese: [String: String] = {
        guard language == "pt" else { return [:] }
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "App/Resources/Localizable.xcstrings")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = json["strings"] as? [String: [String: Any]] else { return [:] }
        var map: [String: String] = [:]
        for (key, entry) in strings {
            let pt = (entry["localizations"] as? [String: Any])?["pt"] as? [String: Any]
            if let value = (pt?["stringUnit"] as? [String: Any])?["value"] as? String { map[key] = value }
        }
        return map
    }()

    /// A label as the app shows it in the test's language.
    func L(_ english: String) -> String { Self.portuguese[english] ?? english }

    /// A label the app looks up by its own key (`LocalizedStringResource("tour.next", defaultValue: "Next")`).
    func L(_ english: String, key: String) -> String { Self.language == "pt" ? Self.portuguese[key] ?? L(english) : english }

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        app?.terminate()
        // A failure here must not try to stop the test (continueAfterFailure false): it would hang the run.
        continueAfterFailure = true
        if !unlabelled.isEmpty {
            XCTFail("Buttons without a VoiceOver label:\n" + unlabelled.joined(separator: "\n"))
        }
    }

    /// Launches the demo, optionally straight onto a `-uiScreen`, and waits for the chat (or that screen) to be up.
    func launch(screen: String? = nil, _ extra: [String] = []) {
        app = XCUIApplication()
        let locale = Self.language == "pt" ? "pt_BR" : "en_US"
        app.launchArguments = ["-uiDemo", "-AppleLanguages", "(\(Self.language))", "-AppleLocale", locale] + extra
        if let screen { app.launchArguments += ["-uiScreen", screen] }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "BOAR didn't start")
        if screen == nil {
            XCTAssertTrue(app.textFields[L("Ask BOAR")].waitForExistence(timeout: 15), "the chat didn't open")
        }
    }

    // MARK: Finding and tapping

    func button(_ english: String) -> XCUIElement { app.buttons[L(english)].firstMatch }
    func toggle(_ english: String) -> XCUIElement { app.switches[L(english)].firstMatch }
    func text(_ english: String) -> XCUIElement { app.staticTexts[L(english)].firstMatch }

    /// Any element whose label is `english` (in the test's language) or starts with it.
    func anything(_ english: String) -> XCUIElement {
        let label = L(english)
        return app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label)).firstMatch
    }

    /// Waits for the element, scrolling the screen's list down (then back up) until it can be tapped.
    @discardableResult
    func reveal(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 5,
                file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        _ = element.waitForExistence(timeout: timeout)
        // Already loaded but cut off: short drags sized to it. A swipe scrolls further than the room a tall row has
        // to land in (the Labs grid's Calculator tile), so swiping can step over it every time.
        var drags = 0
        while element.exists && !onScreen(element) && drags < 16 {
            let window = app.windows.firstMatch.frame
            let f = element.frame
            let below = f.maxY - (window.maxY - 20), above = (window.minY + 95) - f.minY
            if below > 0 { drag(by: -min(below + 40, 300)) } else if above > 0 { drag(by: min(above + 40, 300)) } else { break }
            drags += 1
        }
        var swipes = 0
        // Below the screen (or not loaded yet): scroll down to it; above it: back up.
        while !onScreen(element) && swipes < 10 && !(element.exists && element.frame.maxY < 120) {
            scrollable.swipeUp(velocity: .slow)
            swipes += 1
        }
        swipes = 0
        while !onScreen(element) && swipes < 12 {
            scrollable.swipeDown(velocity: .slow)
            swipes += 1
        }
        if !onScreen(element) {
            XCTFail("\(what) not found on screen\n\(app.debugDescription)", file: file, line: line)
        }
        return element
    }

    /// Tappable and clear of the navigation bar and the screen's bottom edge.
    func onScreen(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let window = app.windows.firstMatch.frame
        let f = element.frame
        // A button in the navigation bar.
        let bar = app.navigationBars.firstMatch
        if bar.exists, f.minY >= bar.frame.minY - 4, f.maxY <= bar.frame.maxY + 4 { return true }
        return f.minY >= window.minY + 95 && f.maxY <= window.maxY - 20 || f.height > window.height / 2
    }

    /// Drags the screen's content by `dy` points (negative: up, to see what's below) and holds, so it doesn't coast.
    private func drag(by dy: CGFloat) {
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy < 0 ? 0.7 : 0.3))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)), withVelocity: .slow,
                    thenHoldForDuration: 0.3)
    }

    func tap(_ element: XCUIElement, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        reveal(element, what, file: file, line: line).tap()
        assertRunning(file: file, line: line)
    }

    /// The screen's scrolling list (a Form is a collection view), or the window.
    private var scrollable: XCUIElement {
        let list = app.collectionViews.firstMatch
        if list.exists && list.isHittable { return list }
        let scroll = app.scrollViews.firstMatch
        return scroll.exists && scroll.isHittable ? scroll : app.windows.firstMatch
    }

    /// Back out of a pushed screen with the navigation bar's back button.
    func goBack(file: StaticString = #filePath, line: UInt = #line) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "no back button", file: file, line: line)
        back.tap()
        assertRunning(file: file, line: line)
    }

    /// Closes the sheet on screen: its close/done/cancel button, or a swipe down.
    func closeSheet(file: StaticString = #filePath, line: UInt = #line) {
        for name in ["Close", "Done", "Cancel"] {
            let b = app.navigationBars.buttons[L(name)].firstMatch
            if b.exists && b.isHittable { b.tap(); assertRunning(file: file, line: line); return }
        }
        let close = app.buttons["close"].firstMatch
        if close.exists && close.isHittable { close.tap(); assertRunning(file: file, line: line); return }
        app.swipeDown(velocity: .fast)
        assertRunning(file: file, line: line)
    }

    /// Flips a switch and flips it back, checking that each tap changed it.
    func flipTwice(_ english: String, file: StaticString = #filePath, line: UInt = #line) {
        let s = reveal(toggle(english), "switch \(english)", file: file, line: line)
        guard s.isEnabled else { return }
        let before = s.value as? String
        tapSwitch(s)
        XCTAssertTrue(waitValue(s, not: before), "\(english) didn't change\n\(s.debugDescription)", file: file, line: line)
        tapSwitch(s)
        XCTAssertTrue(waitValue(s, is: before), "\(english) didn't change back", file: file, line: line)
        assertRunning(file: file, line: line)
    }

    /// A SwiftUI switch takes the tap on its knob, at the trailing edge of the row.
    func tapSwitch(_ s: XCUIElement) {
        let knob = s.switches.firstMatch
        (knob.exists ? knob : s).coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    /// Waits up to 2 s for a switch's value to become (or stop being) `value`.
    private func waitValue(_ s: XCUIElement, is value: String? = nil, not other: String? = nil) -> Bool {
        for _ in 0..<10 {
            let v = s.value as? String
            if let other, v != other { return true }
            if other == nil, v == value { return true }
            usleep(200_000)
        }
        return false
    }

    // MARK: Checks

    func assertRunning(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(app.state, .runningForeground, "BOAR is no longer running", file: file, line: line)
    }

    /// Every visible button has a label VoiceOver can read (not empty, not a raw symbol name like "boar.add").
    func auditLabels(_ screen: String) {
        assertRunning()
        for b in app.buttons.allElementsBoundByIndex where b.exists && b.isHittable {
            let label = b.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if label.isEmpty || label.hasPrefix("boar.") {
                // The system keyboard's prediction bar holds unlabelled buttons; they aren't BOAR's.
                if b.frame.minY >= keyboardTop { continue }
                // A List's DisclosureGroup chevron: the system's, beside its labelled row (which VoiceOver reads with
                // its expanded or collapsed state).
                if b.images["collapsed"].exists || b.images["expanded"].exists { continue }
                let entry = "\(screen): \(b.identifier.isEmpty ? "-" : b.identifier) at \(b.frame)\n"
                    + b.debugDescription.split(separator: "\n").prefix(8).joined(separator: "\n")
                if !unlabelled.contains(entry) { unlabelled.append(entry) }
            }
        }
    }

    private var keyboardTop: CGFloat {
        let k = app.keyboards.firstMatch
        return k.exists ? k.frame.minY - 50 : .greatestFiniteMagnitude
    }

    func dismissKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        app.navigationBars.firstMatch.tap()
    }
}
