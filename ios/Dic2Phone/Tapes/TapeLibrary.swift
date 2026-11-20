import Foundation
import Observation

/// The tapes on the deck and on the shelf, as the screens show them.
@MainActor
@Observable
final class TapeLibrary {
    private(set) var deck: [Tape] = []
    private(set) var shelf: [Tape] = []
    /// Why the last change to a tape's title or flags didn't stick, for the deck to show.
    private(set) var problem: String?

    @ObservationIgnored private let store: TapeStore
    @ObservationIgnored private let heard: HeardList

    init(store: TapeStore, heard: HeardList) {
        self.store = store
        self.heard = heard
    }

    var newCount: Int {
        deck.count(where: \.isNew)
    }

    /// The most recent recording on the deck.
    var lastTape: Tape? {
        deck.max { $0.id < $1.id }
    }

    func tapes(in rack: Rack, sortedBy sort: TapeSort) -> [Tape] {
        sort.sorted(rack == .deck ? deck : shelf)
    }

    func tape(_ id: TapeID) -> Tape? {
        deck.first { $0.id == id } ?? shelf.first { $0.id == id }
    }

    /// Where the tapes' files are, to hand to the share sheet.
    func fileURLs(of tapes: [Tape]) -> [URL] {
        tapes.map { store.url(of: $0) }
    }

    func reload() async {
        deck = await store.tapes(in: .deck, heard: heard.ids)
        shelf = await store.tapes(in: .shelf, heard: [])
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

    /// - Returns: how many tapes couldn't be deleted.
    func delete(_ tapes: [Tape]) async -> Int {
        let failures = await store.delete(tapes)
        heard.forget(tapes.map(\.id))
        await reload()
        return failures
    }

    /// - Returns: how many tapes were moved to the shelf.
    func shelve(_ tapes: [Tape]) async -> Int {
        let moved = await store.shelve(tapes)
        heard.forget(tapes.map(\.id))
        await reload()
        return moved
    }

    func setTitle(_ title: String, of tape: Tape) async {
        let trimmed = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(TapeMeta.titleLimit))
        await updateMeta(of: tape) { $0.title = trimmed }
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

    private func updateMeta(of tape: Tape, _ change: @escaping @Sendable (inout TapeMeta) -> Void) async {
        problem = nil
        do {
            try await store.updateMeta(of: tape.id, change)
        } catch {
            problem = String(localized: "Couldn't save")
        }
        await reload()
    }
}
