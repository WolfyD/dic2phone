import CryptoKit
import Foundation

/// All file work in the vault: sealing tapes in, taking them out, and keeping the encrypted
/// index of what's inside. Holds the data key while the vault is open.
///
/// Every operation keeps the key it started with, so a lock halfway through lets it finish
/// instead of leaving half-sealed files, and the index is read fresh each time and written back
/// without an `await` in between, so two operations can never undo each other's changes.
actor VaultStore {
    private let storage: Storage
    private let tapeStore: TapeStore
    private var key: SymmetricKey?

    init(storage: Storage, tapeStore: TapeStore) {
        self.storage = storage
        self.tapeStore = tapeStore
    }

    /// Whether a vault has been made on this phone: not before its first unlock, nor after a reset.
    nonisolated var exists: Bool {
        FileManager.default.fileExists(atPath: storage.vaultIndexURL.path(percentEncoded: false))
    }

    /// Makes a new, empty vault, or checks that `key` opens the one there is.
    func open(with key: SymmetricKey) throws {
        if exists {
            _ = try readIndex(key)
        } else {
            try writeIndex([], key: key)
        }
        self.key = key
        clearUnsealed()
    }

    func close() {
        key = nil
    }

    /// Throws away everything in the vault; offered only once its key is lost.
    func reset() {
        key = nil
        removeContents(of: storage.vault)
    }

    /// The tapes inside, ready to play; none while the vault is locked.
    func tapes() -> [SealedTape] {
        guard let key, let entries = try? readIndex(key) else { return [] }
        return entries.map { entry in
            let meta = readMeta(entry.name, key: key)
            let tape = Tape(
                id: entry.id,
                rack: .vault,
                durationMs: entry.durationMs,
                sizeBytes: entry.sizeBytes,
                isNew: false,
                title: meta.title,
                flags: meta.flags,
                hasCaptions: FileManager.default.fileExists(atPath: storage.sealedCaptionsURL(entry.name).path(percentEncoded: false))
            )
            return SealedTape(tape: tape, file: SealedFile(url: storage.sealedTapeURL(entry.name), key: key))
        }
    }

    /// Seals plain tapes into the vault, and only once each is safely sealed deletes its original.
    func lockAway(_ tapes: [Tape]) async -> LockAwayResult {
        guard let key else { return LockAwayResult(locked: [], leftBehind: 0) }
        var locked: [Tape] = []
        for tape in tapes where tape.rack != .vault {
            let meta = await tapeStore.meta(for: tape.id)
            let transcript = await tapeStore.transcript(of: tape.id)
            if (try? seal(tape, meta: meta, transcript: transcript, key: key)) != nil {
                locked.append(tape)
            }
        }
        let leftBehind = await tapeStore.delete(locked)
        return LockAwayResult(locked: locked, leftBehind: leftBehind)
    }

    /// Unseals vault tapes back onto the shelf, never over a tape already there.
    /// - Returns: how many came out.
    func takeOut(_ tapes: [Tape]) async -> Int {
        guard let key else { return 0 }
        var takenOut = 0
        for tape in tapes where tape.rack == .vault {
            guard let entry = try? entry(for: tape.id, key: key),
                  let meta = try? unseal(entry, key: key)
            else { continue }
            try? await tapeStore.saveMeta(meta, for: tape.id)
            if let transcript = readTranscript(entry.name, key: key) {
                try? await tapeStore.saveTranscript(transcript, for: tape.id)
            }
            try? remove([tape.id], key: key)
            takenOut += 1
        }
        return takenOut
    }

    /// - Returns: how many tapes couldn't be erased.
    func erase(_ tapes: [Tape]) -> Int {
        guard let key, (try? remove(Set(tapes.map(\.id)), key: key)) != nil else { return tapes.count }
        return 0
    }

    func updateMeta(of id: TapeID, _ change: @Sendable (inout TapeMeta) -> Void) throws {
        guard let key else { throw SealedFileError.unwritable }
        let entry = try entry(for: id, key: key)
        var meta = readMeta(entry.name, key: key)
        change(&meta)
        try sealReplacing(JSONEncoder().encode(meta), at: storage.sealedMetaURL(entry.name), name: entry.name, key: key)
    }

    /// Seals `data` beside the file it replaces first, so a failure leaves the old one whole.
    private func sealReplacing(_ data: Data, at url: URL, name: SealedName, key: SymmetricKey) throws {
        let part = storage.sealingURL(name)
        defer { try? FileManager.default.removeItem(at: part) }
        try SealedFileWriter.seal(data, to: part, key: key)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: part)
        } else {
            try FileManager.default.moveItem(at: part, to: url)
        }
    }

    /// Nil while the vault is locked, or if the tape has no captions yet.
    func transcript(of id: TapeID) -> Transcript? {
        guard let key, let entry = try? entry(for: id, key: key) else { return nil }
        return readTranscript(entry.name, key: key)
    }

    func saveTranscript(_ transcript: Transcript, for id: TapeID) throws {
        guard let key else { throw CaptionError.vaultLocked }
        let entry = try entry(for: id, key: key)
        try sealReplacing(Data(SubRip.text(of: transcript.cues).utf8), at: storage.sealedCaptionsURL(entry.name), name: entry.name, key: key)
    }

    /// Plain copies of vault tapes for the share sheet. This is the one time a vault tape is on
    /// disk unencrypted, because other apps can only be handed a file; the copies sit in the
    /// temporary folder until `clearUnsealed()`.
    func sendingCopies(of tapes: [Tape]) -> [URL] {
        guard let key, let entries = try? readIndex(key) else { return [] }
        return tapes.compactMap { tape in
            guard let entry = entries.first(where: { $0.id == tape.id }) else { return nil }
            let copy = storage.sendingURL(tape.id)
            try? FileManager.default.removeItem(at: copy)
            do {
                try SealedFile(url: storage.sealedTapeURL(entry.name), key: key).reader().copy(to: copy)
                return copy
            } catch {
                try? FileManager.default.removeItem(at: copy)
                return nil
            }
        }
    }

    /// Deletes every plain copy: sent ones, and any left by a take-out that was cut off.
    func clearUnsealed() {
        removeContents(of: storage.unsealed)
    }

    private func seal(_ tape: Tape, meta: TapeMeta, transcript: Transcript?, key: SymmetricKey) throws {
        var entries = try readIndex(key)
        guard !entries.contains(where: { $0.id == tape.id }) else { throw SealedFileError.unwritable }
        let name = SealedName.random()
        do {
            let part = storage.sealingURL(name)
            try SealedFileWriter.seal(contentsOf: tapeStore.url(of: tape), to: part, key: key)
            try FileManager.default.moveItem(at: part, to: storage.sealedTapeURL(name))
            try SealedFileWriter.seal(JSONEncoder().encode(meta), to: storage.sealedMetaURL(name), key: key)
            if let transcript {
                try SealedFileWriter.seal(Data(SubRip.text(of: transcript.cues).utf8), to: storage.sealedCaptionsURL(name), key: key)
            }
            entries.append(VaultEntry(
                id: tape.id,
                name: name,
                durationMs: tape.durationMs,
                sizeBytes: tape.sizeBytes,
                addedAtMs: Int64(Date.now.timeIntervalSince1970 * 1000)
            ))
            try writeIndex(entries, key: key)
        } catch {
            removeFiles(of: name)
            throw error
        }
    }

    /// Decrypts a tape onto the shelf.
    /// - Returns: its metadata, to be stored in the open again.
    private func unseal(_ entry: VaultEntry, key: SymmetricKey) throws -> TapeMeta {
        let part = storage.unsealingURL(entry.name)
        do {
            try SealedFile(url: storage.sealedTapeURL(entry.name), key: key).reader().copy(to: part)
            try FileManager.default.moveItem(at: part, to: storage.tapeURL(entry.id, in: .shelf))
        } catch {
            try? FileManager.default.removeItem(at: part)
            throw error
        }
        return readMeta(entry.name, key: key)
    }

    /// Takes tapes out of the index first, so a file that won't delete is only left over, never
    /// listed without its contents.
    private func remove(_ ids: Set<TapeID>, key: SymmetricKey) throws {
        var entries = try readIndex(key)
        let removed = entries.filter { ids.contains($0.id) }
        entries.removeAll { ids.contains($0.id) }
        try writeIndex(entries, key: key)
        removed.forEach { removeFiles(of: $0.name) }
    }

    private func entry(for id: TapeID, key: SymmetricKey) throws -> VaultEntry {
        guard let entry = try readIndex(key).first(where: { $0.id == id }) else { throw SealedFileError.notSealed }
        return entry
    }

    private func readIndex(_ key: SymmetricKey) throws -> [VaultEntry] {
        try VaultIndex.open(Data(contentsOf: storage.vaultIndexURL), key: key)
    }

    private func writeIndex(_ entries: [VaultEntry], key: SymmetricKey) throws {
        try VaultIndex.seal(entries, key: key)
            .write(to: storage.vaultIndexURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    /// Never fails: a tape whose metadata can't be read gets an empty record.
    private func readMeta(_ name: SealedName, key: SymmetricKey) -> TapeMeta {
        guard let json = try? SealedFile(url: storage.sealedMetaURL(name), key: key).reader().readAll(),
              let meta = try? JSONDecoder().decode(TapeMeta.self, from: json)
        else { return TapeMeta() }
        return meta
    }

    private func readTranscript(_ name: SealedName, key: SymmetricKey) -> Transcript? {
        guard let data = try? SealedFile(url: storage.sealedCaptionsURL(name), key: key).reader().readAll(),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return Transcript(cues: SubRip.cues(in: text))
    }

    private func removeFiles(of name: SealedName) {
        let files = [storage.sealingURL(name), storage.sealedTapeURL(name), storage.sealedMetaURL(name), storage.sealedCaptionsURL(name)]
        for url in files {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func removeContents(of folder: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
