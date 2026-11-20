import Foundation
import Observation

/// The tapes on the deck, on the shelf and in the vault, as the screens show them.
@MainActor
@Observable
final class TapeLibrary {
    private(set) var deck: [Tape] = []
    private(set) var shelf: [Tape] = []
    /// Empty while the vault is locked.
    private(set) var vault: [Tape] = []
    /// Why the last change to a tape's title or flags didn't stick, for the deck to show.
    private(set) var problem: String?
    /// Captions read so far. Those of vault tapes are dropped when the vault locks.
    private(set) var transcripts: [TapeID: Transcript] = [:]
    /// As of the last `refreshEffectCopyUsage()`.
    private(set) var effectCopyUsage = EffectCopyUsage()

    @ObservationIgnored private let store: TapeStore
    @ObservationIgnored private let vaultStore: VaultStore
    @ObservationIgnored private let heard: HeardList
    @ObservationIgnored private let effectCopies: EffectCopies
    @ObservationIgnored private var sealedFiles: [TapeID: SealedFile] = [:]
    /// Counts locks, so a reload that started before one can't bring the vault's tapes back.
    @ObservationIgnored private var vaultLocks = 0

    init(store: TapeStore, vaultStore: VaultStore, heard: HeardList, effectCopies: EffectCopies) {
        self.store = store
        self.vaultStore = vaultStore
        self.heard = heard
        self.effectCopies = effectCopies
    }

    var newCount: Int {
        deck.count(where: \.isNew)
    }

    /// The most recent recording on the deck.
    var lastTape: Tape? {
        deck.max { $0.id < $1.id }
    }

    func tapes(in rack: Rack, sortedBy sort: TapeSort) -> [Tape] {
        switch rack {
        case .deck: sort.sorted(deck)
        case .shelf: sort.sorted(shelf)
        case .vault: sort.sorted(vault)
        }
    }

    func tape(_ id: TapeID) -> Tape? {
        [deck, shelf, vault].lazy.joined().first { $0.id == id }
    }

    /// What the player reads a vault tape from; nil while the vault is locked.
    func sealedFile(of tape: Tape) -> SealedFile? {
        sealedFiles[tape.id]
    }

    /// Where the tape's sound is decoded from for captions, silences and CUE; nil for a vault
    /// tape while the vault is locked.
    func source(of tape: Tape) -> TapeSource? {
        guard tape.rack == .vault else { return .plain(store.url(of: tape)) }
        return sealedFiles[tape.id].map(TapeSource.sealed)
    }

    /// Reads the tape's captions into `transcripts`, unless they're there already.
    func loadTranscript(of tape: Tape) async {
        guard tape.hasCaptions, transcripts[tape.id] == nil else { return }
        let locksBefore = vaultLocks
        let transcript = tape.rack == .vault
            ? await vaultStore.transcript(of: tape.id)
            : await store.transcript(of: tape.id)
        guard vaultLocks == locksBefore else { return }
        transcripts[tape.id] = transcript
    }

    func saveTranscript(_ transcript: Transcript, for tape: Tape) async throws {
        if tape.rack == .vault {
            try await vaultStore.saveTranscript(transcript, for: tape.id)
        } else {
            try await store.saveTranscript(transcript, for: tape.id)
        }
        transcripts[tape.id] = transcript
        await reload()
    }

    func reload() async {
        let locksBefore = vaultLocks
        deck = await store.tapes(in: .deck, heard: heard.ids)
        shelf = await store.tapes(in: .shelf, heard: [])
        let sealed = await vaultStore.tapes()
        guard vaultLocks == locksBefore else { return }
        vault = sealed.map(\.tape)
        sealedFiles = Dictionary(sealed.map { ($0.tape.id, $0.file) }, uniquingKeysWith: { first, _ in first })
        transcripts = transcripts.filter { tape($0.key)?.hasCaptions == true }
    }

    /// The vault locked: its tapes go out of sight at once.
    func forgetVault() {
        vaultLocks += 1
        vault = []
        sealedFiles = [:]
        transcripts = transcripts.filter { tape($0.key) != nil }
    }

    func markHeard(_ tapes: [Tape]) {
        let ids = Set(tapes.map(\.id))
        heard.markHeard(ids)
        for index in deck.indices where ids.contains(deck[index].id) {
            deck[index].isNew = false
        }
    }

    func markAllHeard() {
        markHeard(deck)
    }

    /// Files for the share sheet. Vault tapes are unsealed into plain copies first, which
    /// `clearSendingCopies()` deletes once the sheet is done with them.
    func filesToSend(_ tapes: [Tape]) async -> [URL] {
        let plain = tapes.filter { $0.rack != .vault }.map { store.url(of: $0) }
        let sealed = tapes.filter { $0.rack == .vault }
        return sealed.isEmpty ? plain : plain + (await vaultStore.sendingCopies(of: sealed))
    }

    /// The tape's captions as an .srt file for the share sheet. A vault tape's is a plain copy,
    /// which `clearSendingCopies()` deletes.
    func captionsToSend(of tape: Tape) async -> URL? {
        guard tape.hasCaptions else { return nil }
        return tape.rack == .vault ? await vaultStore.sendingCaptions(of: tape.id) : store.captionsURL(of: tape)
    }

    func clearSendingCopies() async {
        await vaultStore.clearUnsealed()
    }

    /// The tape's effect copy, if it's been made. Never for a vault tape.
    func readyEffectCopy(of tape: Tape, with effects: TapeEffects) -> URL? {
        tape.rack == .vault ? nil : effectCopies.ready(tape.id, with: effects)
    }

    /// The tape's effect copy, made first if need be; nil for a vault tape, or if it couldn't
    /// be made.
    func effectCopy(of tape: Tape, with effects: TapeEffects) async -> URL? {
        guard tape.rack != .vault else { return nil }
        return await effectCopies.copy(of: tape.id, from: store.url(of: tape), with: effects)
    }

    func markEffectCopyPlayed(_ copy: URL) {
        Task { await effectCopies.markPlayed(copy) }
    }

    /// Only once the racks are read, or every copy would look like it had lost its tape.
    func tidyEffectCopies(unplayedDays: Int) async {
        let tapes = Set((deck + shelf).map(\.id))
        await effectCopies.tidy(keeping: tapes, unplayedDays: unplayedDays, now: .now)
    }

    func refreshEffectCopyUsage() async {
        effectCopyUsage = await effectCopies.usage()
    }

    func clearEffectCopies() async {
        await effectCopies.clear()
        await refreshEffectCopyUsage()
    }

    /// - Returns: how many tapes couldn't be deleted.
    func delete(_ tapes: [Tape]) async -> Int {
        let plainFailures = await store.delete(tapes.filter { $0.rack != .vault })
        let sealedFailures = await vaultStore.erase(tapes.filter { $0.rack == .vault })
        heard.forget(tapes.map(\.id))
        await effectCopies.forget(Set(tapes.map(\.id)))
        await reload()
        return plainFailures + sealedFailures
    }

    /// - Returns: how many tapes were moved to the shelf.
    func shelve(_ tapes: [Tape]) async -> Int {
        let moved = await store.shelve(tapes)
        heard.forget(tapes.map(\.id))
        await reload()
        return moved
    }

    func lockAway(_ tapes: [Tape]) async -> LockAwayResult {
        await effectCopies.forget(Set(tapes.map(\.id)))
        let result = await vaultStore.lockAway(tapes)
        heard.forget(result.locked.map(\.id))
        await reload()
        return result
    }

    /// - Returns: how many tapes came out onto the shelf.
    func takeOut(_ tapes: [Tape]) async -> Int {
        let takenOut = await vaultStore.takeOut(tapes)
        await reload()
        return takenOut
    }

    /// Everything known about the tape; nil for a vault tape while the vault is locked.
    func meta(of tape: Tape) async -> TapeMeta? {
        tape.rack == .vault ? await vaultStore.meta(of: tape.id) : await store.meta(for: tape.id)
    }

    /// - Returns: whether it was saved.
    func saveInfo(_ draft: TapeInfoDraft, of tape: Tape) async -> Bool {
        await updateMeta(of: tape) { draft.apply(to: &$0) }
    }

    func setTitle(_ title: String, of tape: Tape) async {
        let trimmed = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(TapeMeta.titleLimit))
        await updateMeta(of: tape) { $0.title = trimmed }
    }

    /// An empty note takes the flag's note off.
    func setFlagNote(_ note: String, at flag: Int64, of tape: Tape) async {
        let trimmed = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(TapeMeta.flagNoteLimit))
        await updateMeta(of: tape) { $0.flagNotes[flag] = trimmed.isEmpty ? nil : trimmed }
    }

    func addFlag(atMs ms: Int64, to tape: Tape) async {
        await updateMeta(of: tape) { meta in
            guard !meta.flags.contains(ms) else { return }
            meta.flags = (meta.flags + [ms]).sorted()
        }
    }

    func removeFlag(_ ms: Int64, from tape: Tape) async {
        await updateMeta(of: tape) { $0.flags.removeAll { $0 == ms } }
    }

    @discardableResult
    private func updateMeta(of tape: Tape, _ change: @escaping @Sendable (inout TapeMeta) -> Void) async -> Bool {
        problem = nil
        let saved: Bool
        do {
            if tape.rack == .vault {
                try await vaultStore.updateMeta(of: tape.id, change)
            } else {
                try await store.updateMeta(of: tape.id, change)
            }
            saved = true
        } catch {
            problem = String(localized: "Couldn't save")
            saved = false
        }
        await reload()
        return saved
    }
}
