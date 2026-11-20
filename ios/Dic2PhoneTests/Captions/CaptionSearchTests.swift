import XCTest
@testable import Dic2Phone

final class CaptionSearchTests: XCTestCase {
    private let tape = Tape.fixture("2026-11-19_14-03-22")

    func testIgnoresCaseAndAccents() {
        let hits = search("arvizturo", in: ["Az ÁRVÍZTŰRŐ tükörfúrógép"])

        XCTAssertEqual(hits.map(\.characters), [3..<12])
    }

    func testTheMatchMarksTheOriginalCharacters() throws {
        let text = "Café 👋🏽 crème brûlée"
        let hit = try XCTUnwrap(search("CREME", in: [text]).first)

        let characters = Array(text)
        XCTAssertEqual(String(characters[hit.characters]), "crème")
    }

    func testFindsEveryCueThatSaysIt() {
        let hits = search("tape", in: ["a tape", "nothing", "another TAPE"])

        XCTAssertEqual(hits.map(\.cue.text), ["a tape", "another TAPE"])
    }

    func testABlankQueryFindsNothing() {
        XCTAssertTrue(search("  ", in: ["anything"]).isEmpty)
    }

    func testStopsAtTheHitLimit() {
        let texts = Array(repeating: "word", count: CaptionSearch.maxHits + 10)

        XCTAssertEqual(search("word", in: texts).count, CaptionSearch.maxHits)
    }

    private func search(_ query: String, in texts: [String]) -> [CaptionHit] {
        let cues = texts.enumerated().map { index, text in
            Cue(startMs: Int64(index) * 1_000, endMs: Int64(index) * 1_000 + 500, text: text)
        }
        return CaptionSearch.hits(for: query, in: [(tape, Transcript(cues: cues))])
    }
}
