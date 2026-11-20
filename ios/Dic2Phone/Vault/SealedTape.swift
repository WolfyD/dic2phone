/// A tape in the vault, and its sealed file for the player.
struct SealedTape: Sendable {
    let tape: Tape
    let file: SealedFile
}
