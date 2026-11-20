import XCTest
@testable import Dic2Phone

final class CuePiecesTests: XCTestCase {
    func testWindingOnReadsASecondAtATimeToTheEnd() {
        var pieces = CuePieces(fromMs: 1500, durationMs: 3200, forward: true)
        XCTAssertEqual(pieces.next(), 1500 ..< 2500)
        XCTAssertEqual(pieces.next(), 2500 ..< 3200)
        XCTAssertTrue(pieces.isAllRead)
        XCTAssertNil(pieces.next())
    }

    func testRewindingReadsBackToTheStart() {
        var pieces = CuePieces(fromMs: 1500, durationMs: 3200, forward: false)
        XCTAssertEqual(pieces.next(), 500 ..< 1500)
        XCTAssertFalse(pieces.isAllRead)
        XCTAssertEqual(pieces.next(), 0 ..< 500)
        XCTAssertTrue(pieces.isAllRead)
        XCTAssertNil(pieces.next())
    }

    func testThePositionFollowsWhatsHeardAndStopsAtTheEnds() {
        let onwards = CuePieces(fromMs: 1500, durationMs: 3200, forward: true)
        XCTAssertEqual(onwards.position(afterHearing: 700), 2200)
        XCTAssertEqual(onwards.position(afterHearing: 5000), 3200)
        let back = CuePieces(fromMs: 1500, durationMs: 3200, forward: false)
        XCTAssertEqual(back.position(afterHearing: 700), 800)
        XCTAssertEqual(back.position(afterHearing: 5000), 0)
    }

    func testAStartPastTheEndIsHeldToTheTape() {
        var pieces = CuePieces(fromMs: 9000, durationMs: 3200, forward: true)
        XCTAssertTrue(pieces.isAllRead)
        XCTAssertNil(pieces.next())
    }
}
