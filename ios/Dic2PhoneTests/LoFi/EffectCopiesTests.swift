import AVFoundation
import XCTest
@testable import Dic2Phone

final class EffectCopiesTests: XCTestCase {
    private static let day: TimeInterval = 86_400
    private let now = Date.local(2026, 6, 15, 12, 0, 0)
    private let first = TapeID(startedAt: .local(2026, 6, 1, 9, 0, 0))
    private let second = TapeID(startedAt: .local(2026, 6, 2, 9, 0, 0))
    private let allEffects = TapeEffects()
    private let hissOnly = TapeEffects(hiss: true, muffle: false, wow: false, saturate: false)

    private var root: URL!
    private var storage: Storage!
    private var copies: EffectCopies!

    override func setUpWithError() throws {
        root = try URL.temporaryFolder()
        storage = try Storage.fixture(in: root)
        copies = EffectCopies(storage: storage)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testMakesACopyAsLongAsTheTape() async throws {
        let tape = storage.tapeURL(first, in: .deck)
        try await AssetTapeWriter.recordTone(to: tape, seconds: 2)

        let copy = await copies.copy(of: first, from: tape, with: allEffects)

        XCTAssertEqual(copy, storage.effectCopyURL(first, mask: allEffects.mask))
        XCTAssertEqual(copies.ready(first, with: allEffects), copy)
        XCTAssertNil(copies.ready(first, with: hissOnly))
        let made = try await AVURLAsset(url: try XCTUnwrap(copy)).load(.duration).seconds
        XCTAssertEqual(made, 2, accuracy: 0.1)
        XCTAssertTrue(contents(of: storage.effectDrafts).isEmpty)
    }

    func testTapesAskedForTogetherShareOneCopy() async throws {
        let tape = storage.tapeURL(first, in: .deck)
        try await AssetTapeWriter.recordTone(to: tape, seconds: 1)

        let copies = try XCTUnwrap(copies)
        let (id, effects) = (first, allEffects)
        async let one = copies.copy(of: id, from: tape, with: effects)
        async let other = copies.copy(of: id, from: tape, with: effects)
        let made = await [one, other]

        XCTAssertNotNil(made[0])
        XCTAssertEqual(made[0], made[1])
    }

    func testATapeThatCannotBeReadGetsNoCopy() async throws {
        let junk = storage.tapeURL(first, in: .deck)
        try Data("not audio".utf8).write(to: junk)

        let copy = await copies.copy(of: first, from: junk, with: allEffects)

        XCTAssertNil(copy)
        XCTAssertNil(copies.ready(first, with: allEffects))
        XCTAssertTrue(contents(of: storage.effectDrafts).isEmpty)
    }

    func testForgettingATapeDeletesAllItsCopies() async throws {
        let firstCopies = try [fakeCopy(of: first, with: allEffects), fakeCopy(of: first, with: hissOnly)]
        let secondCopy = try fakeCopy(of: second, with: allEffects)

        await copies.forget([first])

        XCTAssertFalse(firstCopies.contains(where: exists))
        XCTAssertTrue(exists(secondCopy))
    }

    func testTidyingDeletesCopiesOfGoneTapesAndThoseLongUnplayed() async throws {
        let third = TapeID(startedAt: .local(2026, 6, 3, 9, 0, 0))
        let recent = try fakeCopy(of: first, with: allEffects, playedDaysAgo: 29)
        let old = try fakeCopy(of: second, with: allEffects, playedDaysAgo: 31)
        let orphan = try fakeCopy(of: third, with: allEffects)

        await copies.tidy(keeping: [first, second], unplayedDays: 30, now: now)

        XCTAssertTrue(exists(recent))
        XCTAssertFalse(exists(old))
        XCTAssertFalse(exists(orphan))
    }

    func testTidyingWithoutDaysKeepsUnplayedCopies() async throws {
        let old = try fakeCopy(of: first, with: allEffects, playedDaysAgo: 400)

        await copies.tidy(keeping: [first], unplayedDays: 0, now: now)

        XCTAssertTrue(exists(old))
    }

    func testTidyingDeletesDraftsLeftBehind() async throws {
        let draft = storage.effectDraftURL(first, mask: allEffects.mask)
        try Data(count: 10).write(to: draft)

        await copies.tidy(keeping: [first], unplayedDays: 0, now: now)

        XCTAssertFalse(exists(draft))
    }

    func testUsageCountsCopiesAndTheirBytes() async throws {
        _ = try fakeCopy(of: first, with: allEffects, bytes: 100)
        _ = try fakeCopy(of: second, with: hissOnly, bytes: 250)

        let usage = await copies.usage()

        XCTAssertEqual(usage, EffectCopyUsage(count: 2, bytes: 350))
    }

    func testClearingDeletesEveryCopy() async throws {
        _ = try fakeCopy(of: first, with: allEffects)
        _ = try fakeCopy(of: second, with: hissOnly)

        await copies.clear()

        let usage = await copies.usage()
        XCTAssertEqual(usage, EffectCopyUsage())
    }

    func testOnlyEffectCopiesAreTakenForTapes() {
        let copy = storage.effectCopyURL(first, mask: allEffects.mask)

        XCTAssertEqual(storage.tapeID(ofEffectCopy: copy), first)
        XCTAssertNil(storage.tapeID(ofEffectCopy: root.appending(path: "notes.txt")))
        XCTAssertNil(storage.tapeID(ofEffectCopy: root.appending(path: "../../x_tape.m4a")))
    }

    private func fakeCopy(of id: TapeID, with effects: TapeEffects, bytes: Int = 64, playedDaysAgo days: Double = 0) throws -> URL {
        let copy = storage.effectCopyURL(id, mask: effects.mask)
        let files = FileManager.default
        try files.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: copy)
        let played = now.addingTimeInterval(-days * Self.day)
        try files.setAttributes([.modificationDate: played], ofItemAtPath: copy.path(percentEncoded: false))
        return copy
    }

    private func exists(_ file: URL) -> Bool {
        FileManager.default.fileExists(atPath: file.path(percentEncoded: false))
    }

    private func contents(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }
}
