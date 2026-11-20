import XCTest
@testable import Dic2Phone

final class CassetteLabelTests: XCTestCase {
    private let untitled = Tape.fixture("2026-11-19_14-03-22", durationMs: 60_000, isNew: true)
    private let titled = Tape.fixture("2026-11-19_14-03-22", title: "Groceries", durationMs: 60_000)

    func testAnUntitledTapeInTheDeckShowsWhereItIsAt() {
        let label = CassetteLabel.inDeck(untitled, positionMs: 5_000, playing: true)
        XCTAssertEqual(label.title, TapeNames.pretty(untitled.id))
        XCTAssertEqual(label.subtitle, "\(Glyph.play) 0:05 / 1:00")
        XCTAssertFalse(label.handwritten)
    }

    func testATitledTapeInTheDeckIsHandwrittenOverItsDate() {
        let label = CassetteLabel.inDeck(titled, positionMs: 5_000, playing: false)
        XCTAssertEqual(label.title, "Groceries")
        XCTAssertEqual(label.subtitle, TapeNames.pretty(titled.id))
        XCTAssertTrue(label.handwritten)
    }

    func testAnEmptyDeckWithNothingWrittenIsBlank() {
        let label = CassetteLabel.empty(userLabel: "", recording: false, last: nil)
        XCTAssertEqual(label.title, "")
        XCTAssertFalse(label.handwritten)
    }

    func testABlankLabelShowsTheRecording() {
        let label = CassetteLabel.empty(userLabel: "   ", recording: true, last: nil)
        XCTAssertEqual(label.title, "RECORDING…")
        XCTAssertFalse(label.handwritten)
    }

    func testTheUsersWritingStaysOnTheEmptyDeck() {
        let label = CassetteLabel.empty(userLabel: "Lectures", recording: false, last: untitled)
        XCTAssertEqual(label.title, "Lectures")
        XCTAssertTrue(label.handwritten)
        XCTAssertTrue(label.subtitle.hasSuffix("1:00 · NEW"))
    }

    func testTheSampleShowsTheUsersWritingOrAnExample() {
        XCTAssertEqual(CassetteLabel.sample(userLabel: "").title, "My first tape")
        XCTAssertEqual(CassetteLabel.sample(userLabel: "Lectures").title, "Lectures")
        XCTAssertTrue(CassetteLabel.sample(userLabel: "").handwritten)
    }
}
