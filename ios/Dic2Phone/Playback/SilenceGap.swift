/// A long quiet stretch on a tape that SKIP SILENCE jumps over, less a little quiet kept at
/// either end so speech doesn't run together.
struct SilenceGap: Equatable, Sendable {
    /// Right at a gap's end the player has already jumped, or is about to.
    private static let endMarginMs: Int64 = 50

    let fromMs: Int64
    let toMs: Int64

    func isSkippable(atMs ms: Int64) -> Bool {
        ms >= fromMs && ms < toMs - Self.endMarginMs
    }
}
