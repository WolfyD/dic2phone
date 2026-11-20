import Foundation

/// What a tape list is for: browsing the deck's tapes, picking one to load, or the shelf.
enum TapeListMode {
    case deck
    case load
    case shelf

    var rack: Rack {
        self == .shelf ? .shelf : .deck
    }

    var title: String {
        switch self {
        case .deck: String(localized: "TAPES ON DECK")
        case .load: String(localized: "LOAD TAPE")
        case .shelf: String(localized: "THE SHELF")
        }
    }

    var emptyMessage: String {
        switch self {
        case .deck, .load: String(localized: "No tapes on the deck.\nHold \(Glyph.rec) REC to record.")
        case .shelf: String(localized: "Shelf is empty.\nShelve tapes from the deck to keep them for good.")
        }
    }
}
