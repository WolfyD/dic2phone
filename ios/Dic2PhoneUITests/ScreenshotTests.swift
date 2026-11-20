import XCTest

/// Walks through every screen and keeps a screenshot of each, so the look can be checked from
/// CI without a Mac or an iPhone.
final class ScreenshotTests: XCTestCase {
    private static let setupTabs = ["LOOK", "REC", "PLAY", "MORE"]
    private static let rotationTime: TimeInterval = 2

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEveryScreen() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()

        keepScreenshot("01-deck", of: app)
        press("TAPES", in: app)
        keepScreenshot("02-tapes", of: app)
        backToDeck(in: app)
        press("SHELF", in: app)
        keepScreenshot("03-shelf", of: app)
        backToDeck(in: app)
        press("SETUP", in: app)
        for (index, tab) in Self.setupTabs.enumerated() {
            press(tab, in: app)
            keepScreenshot("0\(index + 4)-setup-\(tab.lowercased())", of: app)
        }
        app.swipeUp()
        keepScreenshot("08-setup-more-end", of: app)
        backToDeck(in: app)
        turnSideways()
        keepScreenshot("09-deck-landscape", of: app)
    }

    /// Screenshots don't wait for animations the way taps do, so without the pause the shot
    /// catches the screen halfway through turning.
    @MainActor
    private func turnSideways() {
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: Self.rotationTime)
    }

    @MainActor
    private func press(_ label: String, in app: XCUIApplication) {
        let key = app.buttons[label]
        XCTAssertTrue(key.waitForExistence(timeout: 5), "No \(label) key")
        key.tap()
    }

    /// The back key's arrow glyph carries a variation selector, so it's found by its word.
    @MainActor
    private func backToDeck(in app: XCUIApplication) {
        let back = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", " DECK")).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "No back key")
        back.tap()
    }

    @MainActor
    private func keepScreenshot(_ name: String, of app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
