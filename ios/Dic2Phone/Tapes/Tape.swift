import Foundation

/// One tape as the lists and the deck show it.
struct Tape: Identifiable, Hashable, Sendable {
    let id: TapeID
    let rack: Rack
    let durationMs: Int64
    let sizeBytes: Int64
    var isNew: Bool
    var title: String
    /// Flagged moments, in milliseconds from the start, sorted.
    var flags: [Int64]
    var hasCaptions: Bool

    var recordedAt: Date? { id.recordedAt }
}
