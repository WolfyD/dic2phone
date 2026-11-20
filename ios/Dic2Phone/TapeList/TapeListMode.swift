import Foundation

/// What a tape list is for: browsing the deck's tapes, picking one to load, the shelf, or the
/// vault inside it.
enum TapeListMode {
    case deck
    case load
    case shelf
    case vault

    var rack: Rack {
        switch self {
        case .deck, .load: .deck
        case .shelf: .shelf
        case .vault: .vault
        }
    }

    var title: String {
        switch self {
        case .deck: String(localized: "TAPES ON DECK")
        case .load: String(localized: "LOAD TAPE")
        case .shelf: String(localized: "THE SHELF")
        case .vault: String(localized: "THE VAULT")
        }
    }

    var emptyMessage: String {
        switch self {
        case .deck, .load: String(localized: "No tapes on the deck.\nHold \(Glyph.rec) REC to record.")
        case .shelf: String(localized: "Shelf is empty.\nShelve tapes from the deck to keep them for good.")
        case .vault: String(localized: "The vault is empty.\nSelect tapes on the deck or shelf and press LOCK.")
        }
    }

    var screen: Screen {
        switch self {
        case .deck: .tapes
        case .load: .load
        case .shelf: .shelf
        case .vault: .vault
        }
    }

    /// Where the back key goes: the vault is a compartment of the shelf.
    var back: Screen {
        self == .vault ? .shelf : .deck
    }

    var backLabel: String {
        self == .vault ? String(localized: "\(Glyph.back) SHELF") : String(localized: "\(Glyph.back) DECK")
    }
}
