import Foundation

/// What happened on the tape transport, reported back to the recorder.
enum TapeEvent: Sendable {
    case tapeStarted(part: Int)
    case flagged(count: Int)
    case meter(TapeMeter)
    case tapeFinished(FinishedTape)
    case failed
}
