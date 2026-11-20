import XCTest
@testable import Dic2Phone

final class FlagNeighboursTests: XCTestCase {
    private let flags: [Int64] = [10_000, 20_000, 30_000]

    func testFindsTheFlagsEitherSide() {
        let neighbours = FlagNeighbours(flags: flags, positionMs: 25_000)
        XCTAssertEqual(neighbours.previous, 20_000)
        XCTAssertEqual(neighbours.next, 30_000)
    }

    func testGoingBackJustAfterAFlagSkipsToTheOneBefore() {
        let neighbours = FlagNeighbours(flags: flags, positionMs: 21_000)
        XCTAssertEqual(neighbours.previous, 10_000)
    }

    func testAFlagJustJumpedToIsNotTheNextOne() {
        let neighbours = FlagNeighbours(flags: flags, positionMs: 20_000)
        XCTAssertEqual(neighbours.next, 30_000)
    }

    func testTheFlagJustPassedStaysForHalfAMinute() {
        XCTAssertEqual(FlagNeighbours(flags: flags, positionMs: 19_800).passed, 20_000)
        XCTAssertEqual(FlagNeighbours(flags: flags, positionMs: 29_000).passed, 20_000)
        XCTAssertNil(FlagNeighbours(flags: flags, positionMs: 9_000).passed)
        XCTAssertNil(FlagNeighbours(flags: flags, positionMs: 61_000).passed)
    }

    func testNothingBeforeTheFirstFlagOrAfterTheLast() {
        XCTAssertNil(FlagNeighbours(flags: flags, positionMs: 5_000).previous)
        XCTAssertNil(FlagNeighbours(flags: flags, positionMs: 30_000).next)
        XCTAssertEqual(FlagNeighbours(flags: [], positionMs: 0), FlagNeighbours(flags: [], positionMs: 99_000))
    }
}
