import XCTest
@testable import Dic2Phone

final class TapeInfoDraftTests: XCTestCase {
    func testStartsFromWhatsWrittenOnTheTape() {
        var meta = TapeMeta()
        meta.title = "Groceries"
        meta.tags = ["home", "list"]
        meta.flagNotes = [5_000: "milk"]
        let draft = TapeInfoDraft(meta: meta)
        XCTAssertEqual(draft.title, "Groceries")
        XCTAssertEqual(draft.tags, "home, list")
        XCTAssertEqual(draft.flagNotes, [5_000: "milk"])
    }

    func testTagsSplitOnCommasAndHashesAndKeepEachOnce() {
        var draft = TapeInfoDraft(meta: TapeMeta())
        draft.tags = " work, #idea #Work,, song ,IDEA "
        XCTAssertEqual(draft.tagList, ["work", "idea", "song"])
    }

    func testKeepsNoMoreTagsThanATapeHolds() {
        var draft = TapeInfoDraft(meta: TapeMeta())
        draft.tags = (1...20).map { "tag\($0)" }.joined(separator: ",")
        XCTAssertEqual(draft.tagList.count, TapeMeta.tagsLimit)
    }

    func testSavingTrimsCutsAndDropsEmptyNotes() {
        var draft = TapeInfoDraft(meta: TapeMeta())
        draft.title = "  " + String(repeating: "a", count: 100) + "  "
        draft.notes = "\n remember \n"
        draft.flagNotes = [1_000: "  call back ", 2_000: "   "]
        var meta = TapeMeta()
        meta.flags = [1_000, 2_000]
        meta.durationMs = 60_000
        draft.apply(to: &meta)
        XCTAssertEqual(meta.title.count, TapeMeta.titleLimit)
        XCTAssertEqual(meta.notes, "remember")
        XCTAssertEqual(meta.flagNotes, [1_000: "call back"])
        XCTAssertEqual(meta.flags, [1_000, 2_000])
        XCTAssertEqual(meta.durationMs, 60_000)
    }
}
