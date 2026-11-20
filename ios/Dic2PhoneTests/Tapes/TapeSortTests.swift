import XCTest
@testable import Dic2Phone

final class TapeSortTests: XCTestCase {
    private let morning = Tape.fixture("2026-11-19_09-00-00", durationMs: 60_000)
    private let noon = Tape.fixture("2026-11-19_12-00-00", title: "banana", durationMs: 5_000)
    private let afternoon = Tape.fixture("2026-11-19_15-00-00", title: "Apple", durationMs: 30_000)
    private let evening = Tape.fixture("2026-11-19_18-00-00", durationMs: 1_000)

    private var shuffled: [Tape] { [noon, evening, morning, afternoon] }

    func testNewestFirst() {
        XCTAssertEqual(TapeSort.newest.sorted(shuffled), [evening, afternoon, noon, morning])
    }

    func testOldestFirst() {
        XCTAssertEqual(TapeSort.oldest.sorted(shuffled), [morning, noon, afternoon, evening])
    }

    func testLongestFirst() {
        XCTAssertEqual(TapeSort.longest.sorted(shuffled), [morning, afternoon, noon, evening])
    }

    func testTitledTapesAToZIgnoringCaseThenUntitledNewestFirst() {
        XCTAssertEqual(TapeSort.title.sorted(shuffled), [afternoon, noon, evening, morning])
    }

    func testTapesWithTheSameTitleAreNewestFirst() {
        let older = Tape.fixture("2026-11-19_09-00-00", title: "Apple")
        let newer = Tape.fixture("2026-11-19_10-00-00", title: "apple")
        XCTAssertEqual(TapeSort.title.sorted([older, newer]), [newer, older])
    }

    func testTheSortKeyCyclesThroughEveryOrder() {
        XCTAssertEqual(TapeSort.newest.next, .oldest)
        XCTAssertEqual(TapeSort.oldest.next, .longest)
        XCTAssertEqual(TapeSort.longest.next, .title)
        XCTAssertEqual(TapeSort.title.next, .newest)
    }
}
