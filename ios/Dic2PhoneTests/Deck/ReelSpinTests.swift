import XCTest
@testable import Dic2Phone

final class ReelSpinTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    func testStandsStillUntilItSpins() {
        XCTAssertEqual(ReelSpin().angle(at: start + 10).degrees, 0)
    }

    func testTurnsAtASteadyRate() {
        var spin = ReelSpin()
        spin.update(spinning: true, at: start)
        XCTAssertEqual(spin.angle(at: start + 1).degrees, 220, accuracy: 1e-9)
    }

    func testStaysWhereItStopped() {
        var spin = ReelSpin()
        spin.update(spinning: true, at: start)
        spin.update(spinning: false, at: start + 1)
        XCTAssertEqual(spin.angle(at: start + 60).degrees, 220, accuracy: 1e-9)
    }

    func testCarriesOnFromWhereItStoppedAndWrapsAround() {
        var spin = ReelSpin()
        spin.update(spinning: true, at: start)
        spin.update(spinning: false, at: start + 1)
        spin.update(spinning: true, at: start + 10)
        XCTAssertEqual(spin.angle(at: start + 11).degrees, 80, accuracy: 1e-9)
    }

    func testAFrameStampedBeforeTheStartDoesNotTurnItBack() {
        var spin = ReelSpin()
        spin.update(spinning: true, at: start)
        XCTAssertEqual(spin.angle(at: start - 0.5).degrees, 0)
    }
}
