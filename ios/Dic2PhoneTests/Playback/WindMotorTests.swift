import XCTest
@testable import Dic2Phone

final class WindMotorTests: XCTestCase {
    func testTheMotorSpinsUpOverThreeSeconds() {
        XCTAssertEqual(WindMotor.spinUp(after: .zero), 0)
        XCTAssertEqual(WindMotor.spinUp(after: .milliseconds(1500)), 0.5)
        XCTAssertEqual(WindMotor.spinUp(after: .seconds(3)), 1)
        XCTAssertEqual(WindMotor.spinUp(after: .seconds(10)), 1)
    }

    func testTheTapeWindsSixTimesFasterAtFirstAndThirtyAtFullSpeed() {
        XCTAssertEqual(WindMotor.woundMs(in: .milliseconds(100), spinUp: 0), 600)
        XCTAssertEqual(WindMotor.woundMs(in: .milliseconds(100), spinUp: 1), 3000)
    }

    func testTheMotorPicksUpSlowlyThenFast() {
        let early = WindMotor.woundMs(in: .seconds(1), spinUp: 0.5)
        XCTAssertLessThan(early, (6_000 + 30_000) / 2)
    }
}
