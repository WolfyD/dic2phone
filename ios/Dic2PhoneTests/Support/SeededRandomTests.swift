import XCTest
@testable import Dic2Phone

final class SeededRandomTests: XCTestCase {
    /// The published first output of SplitMix64 from seed 0: the deck's sounds depend on it.
    func testMatchesTheReferenceSplitMix64() {
        var random = SeededRandom(seed: 0)
        XCTAssertEqual(random.next(), 0xE220_A839_7B1D_CDAF)
    }

    func testTheSameTextGivesTheSameSequence() {
        var first = SeededRandom(text: "My first tape")
        var second = SeededRandom(text: "My first tape")
        for _ in 0..<10 {
            XCTAssertEqual(first.next(), second.next())
        }
    }

    func testDifferentTextGivesADifferentSequence() {
        var first = SeededRandom(text: "a")
        var second = SeededRandom(text: "b")
        XCTAssertNotEqual(first.next(), second.next())
    }

    func testDrawsStayInRange() {
        var random = SeededRandom(seed: 42)
        for _ in 0..<10_000 {
            XCTAssertTrue((0..<1).contains(random.unit()))
            XCTAssertTrue((-1..<1).contains(random.signed()))
        }
    }
}
