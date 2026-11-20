import Foundation

/// What the deck shows while recording, refreshed about ten times a second.
struct TapeMeter: Sendable, Equatable {
    /// VU level, 0...1.
    let level: Float
    /// The tape is moving: always, unless noise-activated and it's quiet.
    let rolling: Bool
    /// Length of the current tape so far; skipped silences don't count.
    let tapeMs: Int64
    let vox: Bool
}
