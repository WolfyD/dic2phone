import CryptoKit
import XCTest
@testable import Dic2Phone

final class VaultStoreTests: XCTestCase {
    private var root: URL!
    private var storage: Storage!
    private var tapeStore: TapeStore!
    private var store: VaultStore!
    private let key = SymmetricKey(size: .bits256)
    private let spokenWords = Transcript(cues: [Cue(startMs: 1_000, endMs: 2_000, text: "a secret")])

    override func setUpWithError() throws {
        root = try URL.temporaryFolder()
        storage = try Storage.fixture(in: root)
        tapeStore = TapeStore(storage: storage)
        store = VaultStore(storage: storage, tapeStore: tapeStore)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testTheFirstOpeningMakesAnEmptyVault() async throws {
        XCTAssertFalse(store.exists)
        try await store.open(with: key)
        XCTAssertTrue(store.exists)
        let tapes = await store.tapes()
        XCTAssertTrue(tapes.isEmpty)
    }

    func testAnotherKeyDoesNotOpenTheVault() async throws {
        try await store.open(with: key)
        await store.close()
        do {
            try await store.open(with: SymmetricKey(size: .bits256))
            XCTFail("Opened with the wrong key")
        } catch {}
    }

    func testLockingAwaySealsTheTapeAndRemovesTheOriginal() async throws {
        let (tape, plain) = try await recordedTape(title: "Diary")
        try await store.open(with: key)

        let result = await store.lockAway([tape])

        XCTAssertEqual(result.locked.map(\.id), [tape.id])
        XCTAssertEqual(result.leftBehind, 0)
        XCTAssertFalse(exists(storage.tapeURL(tape.id, in: .deck)))
        XCTAssertFalse(exists(storage.metaURL(tape.id)))
        let sealed = await store.tapes()
        let only = try XCTUnwrap(sealed.first)
        XCTAssertEqual(only.tape.id, tape.id)
        XCTAssertEqual(only.tape.rack, .vault)
        XCTAssertEqual(only.tape.title, "Diary")
        XCTAssertEqual(try only.file.reader().readAll(), plain)
    }

    func testTheVaultFolderDoesNotGiveAwayTapeNames() async throws {
        let (tape, _) = try await recordedTape(title: "Diary")
        try await store.open(with: key)
        _ = await store.lockAway([tape])

        XCTAssertFalse(try vaultFiles().contains { $0.contains(tape.id.baseName) })
    }

    func testTakingOutPutsThePlainTapeOnTheShelf() async throws {
        let (tape, plain) = try await recordedTape(title: "Diary")
        let locked = try await lockedAway(tape)

        let takenOut = await store.takeOut(locked)

        XCTAssertEqual(takenOut, 1)
        XCTAssertEqual(try Data(contentsOf: storage.tapeURL(tape.id, in: .shelf)), plain)
        let meta = await tapeStore.meta(for: tape.id)
        XCTAssertEqual(meta.title, "Diary")
        let left = await store.tapes()
        XCTAssertTrue(left.isEmpty)
        XCTAssertEqual(try vaultFiles(), ["index"])
    }

    func testErasingLeavesOnlyTheIndex() async throws {
        let (tape, _) = try await recordedTape()
        let locked = try await lockedAway(tape)

        let failures = await store.erase(locked)

        XCTAssertEqual(failures, 0)
        let left = await store.tapes()
        XCTAssertTrue(left.isEmpty)
        XCTAssertEqual(try vaultFiles(), ["index"])
    }

    func testALockedVaultTouchesNothing() async throws {
        let (tape, _) = try await recordedTape()
        try await store.open(with: key)
        await store.close()

        let result = await store.lockAway([tape])

        XCTAssertTrue(result.locked.isEmpty)
        XCTAssertTrue(exists(storage.tapeURL(tape.id, in: .deck)))
        let tapes = await store.tapes()
        XCTAssertTrue(tapes.isEmpty)
    }

    func testChangedMetadataStaysSealed() async throws {
        let (tape, _) = try await recordedTape(title: "Diary")
        _ = try await lockedAway(tape)

        try await store.updateMeta(of: tape.id) { $0.title = "Secret" }

        let sealed = await store.tapes()
        XCTAssertEqual(sealed.first?.tape.title, "Secret")
        XCTAssertFalse(exists(storage.metaURL(tape.id)))
    }

    func testSendingCopiesArePlainUntilCleared() async throws {
        let (tape, plain) = try await recordedTape()
        let locked = try await lockedAway(tape)

        let copies = await store.sendingCopies(of: locked)
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(copies.first)), plain)

        await store.clearUnsealed()
        XCTAssertFalse(copies.contains { exists($0) })
    }

    func testCaptionsAreSealedWithTheirTape() async throws {
        let (tape, _) = try await recordedTape()
        try await tapeStore.saveTranscript(spokenWords, for: tape.id)

        let locked = try await lockedAway(tape)

        XCTAssertFalse(exists(storage.captionsURL(tape.id)))
        XCTAssertEqual(locked.first?.hasCaptions, true)
        let sealed = await store.transcript(of: tape.id)
        XCTAssertEqual(sealed, spokenWords)
        for file in try vaultFiles() {
            let contents = try Data(contentsOf: storage.vault.appending(path: file))
            XCTAssertNil(contents.range(of: Data("secret".utf8)), file)
        }
    }

    func testCaptionsMadeInTheVaultComeOutWithTheTape() async throws {
        let (tape, _) = try await recordedTape()
        let locked = try await lockedAway(tape)
        try await store.saveTranscript(spokenWords, for: tape.id)

        _ = await store.takeOut(locked)

        let plain = await tapeStore.transcript(of: tape.id)
        XCTAssertEqual(plain, spokenWords)
        XCTAssertEqual(try vaultFiles(), ["index"])
    }

    func testALockedVaultTakesNoCaptions() async throws {
        let (tape, _) = try await recordedTape()
        _ = try await lockedAway(tape)
        await store.close()

        do {
            try await store.saveTranscript(spokenWords, for: tape.id)
            XCTFail("Saved captions into a locked vault")
        } catch {
            XCTAssertEqual(error as? CaptionError, .vaultLocked)
        }
    }

    func testResettingEmptiesTheVault() async throws {
        let (tape, _) = try await recordedTape()
        _ = try await lockedAway(tape)

        await store.reset()

        XCTAssertFalse(store.exists)
        XCTAssertEqual(try vaultFiles(), [])
    }

    private func recordedTape(title: String = "") async throws -> (Tape, Data) {
        let tape = Tape.fixture("2026-11-19_14-03-22", title: title, durationMs: 5_000)
        let plain = RandomBytes.make(2 * SealedFormat.chunkSize + 321)
        try plain.write(to: storage.tapeURL(tape.id, in: .deck))
        var meta = TapeMeta()
        meta.title = title
        try await tapeStore.saveMeta(meta, for: tape.id)
        return (tape, plain)
    }

    /// Opens the vault and locks `tape` away.
    /// - Returns: the tape as the vault lists it.
    private func lockedAway(_ tape: Tape) async throws -> [Tape] {
        try await store.open(with: key)
        _ = await store.lockAway([tape])
        return await store.tapes().map(\.tape)
    }

    private func vaultFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: storage.vault.path(percentEncoded: false)).sorted()
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}
