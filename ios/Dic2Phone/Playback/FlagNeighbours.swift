/// The flags around the deck's position: either side, for the ◀⚑ and ⚑▶ keys, and the one just
/// passed, whose note shows under the time window.
struct FlagNeighbours: Equatable {
    /// Going back from just after a flag goes to the one before it, like a CD's |◀◀.
    private static let backReachMs: Int64 = 1500
    /// A flag just jumped to doesn't count as the next one.
    private static let aheadMarginMs: Int64 = 300
    /// How long after a flag the deck still shows its note.
    private static let noteLingerMs: Int64 = 30_000

    let previous: Int64?
    let next: Int64?
    let passed: Int64?

    /// `flags` sorted, as a tape keeps them.
    init(flags: [Int64], positionMs: Int64) {
        previous = flags.last { $0 < positionMs - Self.backReachMs }
        next = flags.first { $0 > positionMs + Self.aheadMarginMs }
        passed = flags.last { $0 <= positionMs + Self.aheadMarginMs && positionMs - $0 < Self.noteLingerMs }
    }
}
