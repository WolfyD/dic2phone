import XCTest
@testable import Dic2Phone

final class FaderNotchesTests: XCTestCase {
    private let notches = FaderNotches(width: 148, count: 5)

    func testNotchesSpreadEvenlyInsideTheInset() {
        XCTAssertEqual(notches.x(of: 0), 14)
        XCTAssertEqual(notches.x(of: 4), 134)
        XCTAssertEqual(notches.step, 30)
    }

    func testATouchPicksTheNearestNotch() {
        XCTAssertEqual(notches.nearest(to: 42), 1)
        XCTAssertEqual(notches.nearest(to: 76), 2)
    }

    func testTouchesPastTheEndsPickTheEndNotches() {
        XCTAssertEqual(notches.nearest(to: -20), 0)
        XCTAssertEqual(notches.nearest(to: 400), 4)
    }

    func testATooNarrowFaderStillHasAStep() {
        XCTAssertGreaterThan(FaderNotches(width: 0, count: 5).step, 0)
        XCTAssertEqual(FaderNotches(width: 100, count: 1).nearest(to: 80), 0)
    }

    func testSpeedsPrintAsOnTheDial() {
        XCTAssertEqual(Settings.playSpeeds.map(VarispeedArt.mark), ["¾", "1", "1¼", "1½", "2"])
    }
}
