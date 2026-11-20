import Foundation

/// One press of REC until STOP. A long session can produce several tapes (hour splits).
@MainActor
final class RecordingSession {
    let source: String
    var latched: Bool
    /// Noise-activated: silence is left off the tape.
    var gated = false
    var engine: TapeEngine?
    var mic: (any MicInput)?
    var startTask: Task<Void, Never>?
    var feedTask: Task<Void, Never>?
    var keptTapes: [TapeID] = []
    var silent = false
    var failed = false

    init(source: String, latched: Bool) {
        self.source = source
        self.latched = latched
    }
}
