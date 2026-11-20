/// How locking tapes away went.
struct LockAwayResult: Sendable {
    /// The tapes now in the vault.
    let locked: [Tape]
    /// How many of those are still outside too, because their plain files couldn't be deleted.
    let leftBehind: Int
}
