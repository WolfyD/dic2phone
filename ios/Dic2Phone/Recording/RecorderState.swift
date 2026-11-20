import Foundation

/// What the deck shows about recording.
struct RecorderState: Equatable {
    var recording = false
    var startedAt = Date.distantPast
    /// VU level, 0...1.
    var level: Float = 0
    var error: String?
    /// Stays on by itself until stopped, instead of recording only while REC is held.
    var latched = false
    /// Noise-activated: the tape only moves while there's sound.
    var vox = false
    var rolling = true
    /// Length of the current tape so far; silences the gate skipped don't count.
    var tapeMs: Int64 = 0
    var flags = 0
    /// Which tape of a long session this is; sessions roll onto a new tape every hour.
    var part = 0

    /// The reels turn: recording, and not idling on silence under noise activation.
    var tapeMoving: Bool {
        recording && (!vox || rolling)
    }
}
