import Foundation

/// Where a tape is kept: the deck holds new and current tapes, the shelf holds old ones
/// (and is visible in the Files app), and the vault holds tapes sealed away behind Face ID.
enum Rack: String, CaseIterable, Sendable {
    case deck
    case shelf
    case vault

    /// The racks whose tapes are plain files named after their `TapeID`; the vault's are
    /// sealed under random names.
    static let plain: [Rack] = [.deck, .shelf]
}
