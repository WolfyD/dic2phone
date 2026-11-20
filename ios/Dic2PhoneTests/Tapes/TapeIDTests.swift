import XCTest
@testable import Dic2Phone

final class TapeIDTests: XCTestCase {
    func testAcceptsARecordingStamp() {
        XCTAssertEqual(TapeID("2026-11-19_14-03-22.m4a")?.baseName, "2026-11-19_14-03-22")
    }

    func testAcceptsACopyNumberOfUpToFourDigits() {
        XCTAssertNotNil(TapeID("2026-11-19_14-03-22_2.m4a"))
        XCTAssertNotNil(TapeID("2026-11-19_14-03-22_9999.m4a"))
    }

    func testRejectsEveryOtherName() {
        let names = [
            "",
            ".m4a",
            "2026-11-19_14-03-22",
            "2026-11-19_14-03-22.mp3",
            "2026-11-19_14-03-22.m4a.json",
            "2026-11-19_14-03-22_.m4a",
            "2026-11-19_14-03-22_12345.m4a",
            "2026-11-19_14-03-22x.m4a",
            "2026-11-19 14-03-22.m4a",
            "../2026-11-19_14-03-22.m4a",
            "2026-11-19_14-03-22_2/../x.m4a",
            "２026-11-19_14-03-22.m4a",
        ]
        for name in names {
            XCTAssertNil(TapeID(name), name)
        }
    }

    func testIsNamedAfterWhenItStarted() {
        let start = Date.local(2026, 11, 19, 14, 3, 22)
        XCTAssertEqual(TapeID(startedAt: start).fileName, "2026-11-19_14-03-22.m4a")
        XCTAssertEqual(TapeID(startedAt: start, copy: 3).fileName, "2026-11-19_14-03-22_3.m4a")
        XCTAssertEqual(TapeID(startedAt: start).recordedAt, start)
    }

    func testSortsByRecordingTimeWithCopiesAfterTheOriginal() {
        let first = TapeID("2026-11-19_14-03-22.m4a")!
        let copy = TapeID("2026-11-19_14-03-22_2.m4a")!
        let later = TapeID("2026-11-19_14-03-23.m4a")!
        XCTAssertEqual([later, copy, first].sorted(), [first, copy, later])
    }
}
