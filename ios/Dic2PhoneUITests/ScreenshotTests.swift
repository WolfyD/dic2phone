import XCTest

/// Walks through every screen and keeps a screenshot of each, so the look can be checked from
/// CI without a Mac or an iPhone.
final class ScreenshotTests: XCTestCase {
    private static let setupTabs = ["LOOK", "REC", "PLAY", "MORE"]
    private static let firstSetupShot = 5
    private static let rotationTime: TimeInterval = 2

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEveryScreen() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()

        keepScreenshot("01-deck")
        press("TAPES", in: app)
        keepScreenshot("02-tapes")
        back(to: "DECK", in: app)
        press("SHELF", in: app)
        keepScreenshot("03-shelf")
        press("THE VAULT", in: app)
        keepScreenshot("04-vault")
        back(to: "SHELF", in: app)
        back(to: "DECK", in: app)
        press("SETUP", in: app)
        for (index, tab) in Self.setupTabs.enumerated() {
            press(tab, in: app)
            keepScreenshot("0\(Self.firstSetupShot + index)-setup-\(tab.lowercased())")
        }
        app.swipeUp()
        keepScreenshot("09-setup-more-end")
        back(to: "DECK", in: app)
        turnSideways()
        keepScreenshot("10-deck-landscape")
    }

    /// Screenshots don't wait for animations the way taps do, so without the pause the shot
    /// may catch the screen halfway through turning.
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
    private func back(to screen: String, in app: XCUIApplication) {
        let back = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", " \(screen)")).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "No back key to \(screen)")
        back.tap()
    }

    /// The whole screen rather than `app.screenshot()`, which crops a sideways app to a
    /// portrait-shaped window.
    @MainActor
    private func keepScreenshot(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
