import XCTest

/// Settings → See the Tour: every card with Next and Back, the theme card's chips (the whole tour, bars included,
/// follows a theme picked there), and Done back to Settings. Skipped in a build without the tour.
final class TourUITests: BoarUITestCase {
    func testTour() throws {
        launch()
        let back = app.navigationBars.buttons["BackButton"].firstMatch
        if back.waitForExistence(timeout: 3) { back.tap() }
        tap(button("Settings"), "Settings")
        let see = button("See the Tour")
        for _ in 0..<12 where !onScreen(see) { app.collectionViews.firstMatch.swipeUp(velocity: .slow) }
        guard see.exists else { throw XCTSkip("this build has no tour") }
        tap(see, "See the Tour")
        XCTAssertTrue(app.navigationBars[L("BOAR tour")].waitForExistence(timeout: 5), "the tour didn't open")

        var cards = 1
        while next.exists {
            auditLabels("tour card \(cards)")
            if cards == 2 { checkThemeChips() }
            tap(next, "Next")
            cards += 1
            XCTAssertLessThan(cards, 20, "Next never ends")
        }
        auditLabels("tour last card")
        XCTAssertEqual(cards, 11, "the tour should have Android's 11 cards (experimental build)")
        // Back goes to the previous card, Next returns.
        tap(button("Back"), "Back")
        XCTAssertTrue(next.waitForExistence(timeout: 3), "Back didn't go to the previous card")
        tap(next, "Next")
        // The last card's Done (the bottom button, not the bar's) closes the tour.
        let done = app.buttons.matching(NSPredicate(format: "label == %@", L("Done", key: "tour.done"))).allElementsBoundByIndex
            .max { $0.frame.minY < $1.frame.minY }
        XCTAssertNotNil(done)
        if let done { tap(done, "Done") }
        XCTAssertTrue(app.navigationBars[L("Settings")].waitForExistence(timeout: 5), "Done didn't come back to Settings")
    }

    private var next: XCUIElement { app.buttons[L("Next", key: "tour.next")].firstMatch }

    /// Campfire repaints the tour, its navigation bar included; System puts it back.
    private func checkThemeChips() {
        let light = barBrightness() > 0.5
        chip("Campfire").tap()
        assertRunning()
        sleep(1)
        if light {
            XCTAssertLessThan(barBrightness(), 0.5, "the tour's bar stayed light under Campfire")
        }
        chip("System").tap()
        assertRunning()
        sleep(1)
        if light {
            XCTAssertGreaterThan(barBrightness(), 0.5, "the tour's bar didn't come back to Paper")
        }
    }

    private func chip(_ english: String) -> XCUIElement {
        let c = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", L(english))).firstMatch
        XCTAssertTrue(c.waitForExistence(timeout: 3), "theme chip \(english) not found")
        return c
    }

    /// The brightness (0–1) of the navigation bar's background, left of the title.
    private func barBrightness() -> Double {
        let bar = app.navigationBars.firstMatch.frame
        let shot = XCUIScreen.main.screenshot().image
        guard let cg = shot.cgImage else { return 0 }
        let scale = CGFloat(cg.width) / shot.size.width
        let x = Int((bar.minX + 8) * scale), y = Int((bar.midY) * scale)
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(cg, in: CGRect(x: -x, y: y - cg.height + 1, width: cg.width, height: cg.height))
        return (Double(pixel[0]) * 0.299 + Double(pixel[1]) * 0.587 + Double(pixel[2]) * 0.114) / 255
    }
}
