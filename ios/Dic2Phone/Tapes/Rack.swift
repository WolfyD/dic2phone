import Foundation

/// Where a tape is kept: the deck holds new and current tapes, the shelf holds old ones
/// (and is visible in the Files app).
enum Rack: String, CaseIterable, Sendable {
    case deck
    case shelf
}
