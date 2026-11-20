import XCTest
@testable import Dic2Phone

final class SubRipTests: XCTestCase {
    func testWritesNumberedTimedCues() {
        let cues = [
            Cue(startMs: 0, endMs: 1_500, text: "Hello"),
            Cue(startMs: 3_723_004, endMs: 3_725_000, text: "Two\nlines"),
        ]

        XCTAssertEqual(SubRip.text(of: cues), """
        1
        00:00:00,000 --> 00:00:01,500
        Hello

        2
        01:02:03,004 --> 01:02:05,000
        Two
        lines


        """)
    }

    func testReadsBackWhatItWrites() {
        let cues = [
            Cue(startMs: 1_000, endMs: 2_000, text: "One"),
            Cue(startMs: 2_500, endMs: 4_000, text: "Two\nlines"),
        ]

        XCTAssertEqual(SubRip.cues(in: SubRip.text(of: cues)), cues)
    }

    func testReadsOtherWritersFiles() {
        let file = "1\r\n00:00:01.5 --> 00:00:02.25\r\n  Spaced out  \r\n\r\n2\r\n00:00:03,000-->00:00:04,000\r\nTight\r\n"

        XCTAssertEqual(SubRip.cues(in: file), [
            Cue(startMs: 1_500, endMs: 2_250, text: "Spaced out"),
            Cue(startMs: 3_000, endMs: 4_000, text: "Tight"),
        ])
    }

    func testSkipsWhatIsNotACue() {
        let file = "garbage\n99:99\n\n1\n00:00:01,000 --> 00:00:02,000\nKept\n\nmore garbage\n"

        XCTAssertEqual(SubRip.cues(in: file), [Cue(startMs: 1_000, endMs: 2_000, text: "Kept")])
    }

    func testIgnoresHoursTooLongToBeATape() {
        XCTAssertTrue(SubRip.cues(in: "99999999999:00:00,000 --> 99999999999:00:01,000\nNo\n").isEmpty)
    }

    func testAnEmptyFileHasNoCues() {
        XCTAssertTrue(SubRip.cues(in: "").isEmpty)
    }
}
