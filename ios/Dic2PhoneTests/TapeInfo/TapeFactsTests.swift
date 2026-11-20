import XCTest
@testable import Dic2Phone

final class TapeFactsTests: XCTestCase {
    private let tape = Tape.fixture("2026-11-19_14-03-22", durationMs: 245_000)

    func testABareTapeShowsWhatCanBeWorkedOut() {
        let facts = TapeFacts.of(tape, meta: TapeMeta())
        XCTAssertEqual(facts.map(\.name), ["RECORDED", "LENGTH", "SIZE", "FORMAT", "FLAGS", "FILE"])
        XCTAssertEqual(value("RECORDED", in: facts), TapeNames.pretty(tape.id))
        XCTAssertEqual(value("LENGTH", in: facts), "4:05")
        XCTAssertEqual(value("FORMAT", in: facts), TapeFormat.label)
        XCTAssertEqual(value("FILE", in: facts), "2026-11-19_14-03-22  (deck)")
    }

    func testARecordedTapeShowsHowItWasRecorded() {
        var meta = TapeMeta()
        meta.part = 2
        meta.source = "split"
        meta.vox = true
        meta.cuts = 3
        meta.skippedMs = 12_000
        meta.flags = [1_000]
        let facts = TapeFacts.of(tape, meta: meta)
        XCTAssertEqual(value("LENGTH", in: facts), "4:05  ·  TAPE 2")
        XCTAssertEqual(value("STARTED BY", in: facts), "Continued from the previous hour")
        XCTAssertEqual(value("MODE", in: facts), "held · noise-activated, 3 silences cut (0:12)")
        XCTAssertNil(value("FLAGS", in: facts))
    }

    func testAnUnknownSourceIsShownAsItIs() {
        XCTAssertEqual(TapeFacts.startedBy("shortcut"), "shortcut")
        XCTAssertEqual(TapeFacts.startedBy("widget:big"), "Home-screen widget")
    }

    private func value(_ name: String, in facts: [TapeFact]) -> String? {
        facts.first { $0.name == name }?.value
    }
}
