import Foundation

/// How one tape in a list stands: picked, playing, in the deck, being transcribed, soon tidied
/// away.
struct TapeRowState {
    let selected: Bool
    let playing: Bool
    /// How far it has played, 0...1; only meaningful while playing.
    let progress: CGFloat
    let inDeck: Bool
    let transcribing: Bool
    /// When AUTO-TIDY deletes it, if that's within its warning days.
    let tidiedAt: Date?
}
