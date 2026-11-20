import XCTest
@testable import Dic2Phone

final class TapeNamesTests: XCTestCase {
    func testDurationRoundsToTheSecond() {
        XCTAssertEqual(TapeNames.duration(ms: 0), "0:00")
        XCTAssertEqual(TapeNames.duration(ms: 499), "0:00")
        XCTAssertEqual(TapeNames.duration(ms: 500), "0:01")
        XCTAssertEqual(TapeNames.duration(ms: 59_600), "1:00")
        XCTAssertEqual(TapeNames.duration(ms: 245_000), "4:05")
    }

    func testDurationShowsHoursPastAnHour() {
        XCTAssertEqual(TapeNames.duration(ms: 3_600_000), "1:00:00")
        XCTAssertEqual(TapeNames.duration(ms: 3_723_000), "1:02:03")
    }

    func testDateIsDayMonthYearInCapitals() {
        let date = Date.local(2026, 11, 19, 14, 3, 22)
        XCTAssertEqual(TapeNames.date(date, locale: Locale(identifier: "en_US_POSIX")), "19 NOV 2026")
    }

    func testTimeIsOnTheTwentyFourHourClock() {
        XCTAssertEqual(TapeNames.time(.local(2026, 11, 19, 21, 5, 9)), "21:05:09")
    }

    func testAnImpossibleStampFallsBackToTheFileName() {
        let id = TapeID("2026-13-45_99-99-99.m4a")!
        let named = TapeNames.dateAndTime(id)
        XCTAssertEqual(named.date, id.baseName)
        XCTAssertEqual(named.time, "")
    }

    func testATapeIsLabelledByItsTitleOrElseItsDate() {
        let untitled = Tape.fixture("2026-11-19_14-03-22")
        let titled = Tape.fixture("2026-11-19_14-03-22", title: "Groceries")
        XCTAssertEqual(TapeNames.label(titled), "Groceries")
        XCTAssertEqual(TapeNames.label(untitled), TapeNames.pretty(untitled.id))
    }
}
