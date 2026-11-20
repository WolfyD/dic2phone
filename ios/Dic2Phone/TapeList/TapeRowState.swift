import Foundation

/// How one tape in a list stands: picked, playing, in the deck, being transcribed.
struct TapeRowState {
    let selected: Bool
    let playing: Bool
    /// How far it has played, 0...1; only meaningful while playing.
    let progress: CGFloat
    let inDeck: Bool
    let transcribing: Bool
}
