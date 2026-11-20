/// The flags either side of the deck's position, for the ◀⚑ and ⚑▶ keys.
struct FlagNeighbours: Equatable {
    /// Going back from just after a flag goes to the one before it, like a CD's |◀◀.
    private static let backReachMs: Int64 = 1500
    /// A flag just jumped to doesn't count as the next one.
    private static let aheadMarginMs: Int64 = 300

    let previous: Int64?
    let next: Int64?

    /// `flags` sorted, as a tape keeps them.
    init(flags: [Int64], positionMs: Int64) {
        previous = flags.last { $0 < positionMs - Self.backReachMs }
        next = flags.first { $0 > positionMs + Self.aheadMarginMs }
    }
}
