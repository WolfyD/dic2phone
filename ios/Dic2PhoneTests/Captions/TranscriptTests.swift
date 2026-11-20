import XCTest
@testable import Dic2Phone

final class TranscriptTests: XCTestCase {
    private let transcript = Transcript(cues: [
        Cue(startMs: 1_000, endMs: 2_000, text: "First"),
        Cue(startMs: 2_200, endMs: 3_000, text: "second"),
        Cue(startMs: 10_000, endMs: 12_000, text: " Later "),
    ])

    func testNothingIsSaidBeforeTheFirstCue() {
        XCTAssertNil(transcript.cue(atMs: 999))
    }

    func testFindsTheCueBeingSpoken() {
        XCTAssertEqual(transcript.cue(atMs: 1_000)?.text, "First")
        XCTAssertEqual(transcript.cue(atMs: 2_100)?.text, "First")
        XCTAssertEqual(transcript.cue(atMs: 2_200)?.text, "second")
        XCTAssertEqual(transcript.index(atMs: 11_000), 2)
    }

    func testACueLingersBrieflyThenClears() {
        XCTAssertEqual(transcript.cue(atMs: 4_500)?.text, "second")
        XCTAssertNil(transcript.cue(atMs: 4_501))
        XCTAssertNil(transcript.cue(atMs: 20_000))
    }

    func testAnEmptyTranscriptHasNothingToShow() {
        XCTAssertNil(Transcript(cues: []).cue(atMs: 0))
    }

    func testReadableTextBreaksParagraphsAtPauses() {
        XCTAssertEqual(transcript.readable(heading: "Tape"), """
        Tape

        [0:01] First second

        [0:10] Later

        """)
    }
}
