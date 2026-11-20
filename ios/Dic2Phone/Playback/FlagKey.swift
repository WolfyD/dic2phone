import Observation

/// The FLAG key for the tape in the deck. It flags the moment just before now; on a flag (one
/// just set, jumped to, or a moment past) it becomes UNFLAG and takes that flag off.
@MainActor
@Observable
final class FlagKey {
    /// How far past a flag the deck still counts as on it.
    private static let reachBehindMs: Int64 = 2500
    private static let reachAheadMs: Int64 = 300
    /// A flag just set can be taken back this long, wherever the tape has moved on to.
    private static let undoWindow: Duration = .seconds(3)

    private var justSet: (tape: TapeID, ms: Int64)?

    @ObservationIgnored private let player: Player
    @ObservationIgnored private let library: TapeLibrary
    @ObservationIgnored private var undoExpiry: Task<Void, Never>?

    init(player: Player, library: TapeLibrary) {
        self.player = player
        self.library = library
    }

    /// The flag the key would take off, if the deck is on one.
    var flagHere: Int64? {
        guard let tape = player.loaded else { return nil }
        if let justSet, justSet.tape == tape.id { return justSet.ms }
        let position = player.deckPositionMs
        return tape.flags.last { (position - Self.reachBehindMs)...(position + Self.reachAheadMs) ~= $0 }
    }

    func toggle() {
        guard let tape = player.loaded else { return }
        if let flag = flagHere {
            setJustSet(nil)
            Task { await library.removeFlag(flag, from: tape) }
        } else {
            let at = max(player.deckPositionMs - TapeEngine.flagLeadMs, 0)
            setJustSet((tape.id, at))
            Task { await library.addFlag(atMs: at, to: tape) }
        }
    }

    private func setJustSet(_ flag: (tape: TapeID, ms: Int64)?) {
        undoExpiry?.cancel()
        justSet = flag
        guard flag != nil else { return }
        undoExpiry = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            self?.justSet = nil
        }
    }
}
