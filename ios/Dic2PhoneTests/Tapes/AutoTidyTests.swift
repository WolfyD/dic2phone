import XCTest
@testable import Dic2Phone

final class AutoTidyTests: XCTestCase {
    private let heard = Tape.fixture("2026-06-01_10-00-00", durationMs: 60_000)
    private let weekLater = Date.local(2026, 6, 8, 10, 1, 0)

    func testAHeardTapeGoesThatManyDaysAfterItEnded() {
        let tidy = AutoTidy(days: 7, kept: [])
        XCTAssertEqual(tidy.due(in: [heard]), [heard.id: weekLater])
    }

    func testOffTidiesNothing() {
        XCTAssertEqual(AutoTidy(days: 0, kept: []).due(in: [heard]), [:])
    }

    func testUnheardTitledFlaggedAndLoadedTapesAreKept() {
        var flagged = Tape.fixture("2026-06-01_11-00-00")
        flagged.flags = [500]
        let deck = [
            Tape.fixture("2026-06-01_12-00-00", isNew: true),
            Tape.fixture("2026-06-01_13-00-00", title: "Lecture"),
            flagged,
            heard,
        ]
        XCTAssertEqual(AutoTidy(days: 7, kept: [heard.id]).due(in: deck), [:])
    }

    func testTapesDueWithinThreeDaysAreDueSoon() {
        let tidy = AutoTidy(days: 7, kept: [])
        XCTAssertEqual(tidy.dueSoon(in: [heard], now: weekLater.addingTimeInterval(-3 * 86_400)).count, 1)
        XCTAssertEqual(tidy.dueSoon(in: [heard], now: weekLater.addingTimeInterval(-4 * 86_400)).count, 0)
    }

    func testOnlyOverdueTapesGo() {
        let tidy = AutoTidy(days: 7, kept: [])
        XCTAssertEqual(tidy.overdue(in: [heard], now: weekLater.addingTimeInterval(-1)), [])
        XCTAssertEqual(tidy.overdue(in: [heard], now: weekLater), [heard])
    }

    func testWhenIsSaidInDays() {
        let now = Date.local(2026, 6, 8, 10, 0, 0)
        XCTAssertEqual(AutoTidy.whenText(of: now.addingTimeInterval(-1), now: now), "SOON")
        XCTAssertEqual(AutoTidy.whenText(of: now.addingTimeInterval(3_600), now: now), "TODAY")
        XCTAssertEqual(AutoTidy.whenText(of: now.addingTimeInterval(90_000), now: now), "TOMORROW")
        XCTAssertEqual(AutoTidy.whenText(of: now.addingTimeInterval(2.5 * 86_400), now: now), "IN 2 DAYS")
    }
}
