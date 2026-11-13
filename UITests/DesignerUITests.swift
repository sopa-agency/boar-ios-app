import XCTest

/// Boar Designer's gallery (three demo pictures, `-uiDesigner YES`): a picture opens in a sheet that stays open while
/// the device turns (it hangs behind the whole lab page, not on the gallery's row), and its Delete removes it.
final class DesignerUITests: BoarUITestCase {
    func testGallery() {
        launch(screen: "lab-image", ["-labs.enabled.image", "YES", "-uiDesigner", "YES"])
        let pictures = app.buttons.matching(identifier: "designer.picture")
        XCTAssertTrue(pictures.firstMatch.waitForExistence(timeout: 10), "no pictures in the gallery\n\(app.debugDescription)")
        XCTAssertEqual(pictures.count, 3)
        auditLabels("designer")
        tap(pictures.firstMatch, "the first picture")
        let done = button("Done")
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the picture didn't open\n\(app.debugDescription)")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        XCTAssertTrue(done.exists, "the picture closed when the device turned")
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
        XCTAssertTrue(done.exists, "the picture closed when the device turned back")
        auditLabels("designer picture")
        tap(button("Delete"), "Delete")
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "Delete didn't close the picture")
        XCTAssertEqual(pictures.count, 2, "Delete didn't remove the picture")
    }
}
