@testable import Dic2Phone

/// Lets a test pick one kind of event out of a list without a switch each time.
extension TapeEvent {
    var startedPart: Int? {
        switch self {
        case .tapeStarted(let part): part
        default: nil
        }
    }

    var flagCount: Int? {
        switch self {
        case .flagged(let count): count
        default: nil
        }
    }

    var meter: TapeMeter? {
        switch self {
        case .meter(let meter): meter
        default: nil
        }
    }

    var finishedTape: FinishedTape? {
        switch self {
        case .tapeFinished(let tape): tape
        default: nil
        }
    }

    var isFailure: Bool {
        switch self {
        case .failed: true
        default: false
        }
    }
}
