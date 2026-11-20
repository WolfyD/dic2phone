import Foundation

/// Setup's pages, picked with a row of keys at the top.
enum SetupTab: CaseIterable {
    case look
    case rec
    case play
    case more

    var label: String {
        switch self {
        case .look: String(localized: "LOOK")
        case .rec: String(localized: "REC")
        case .play: String(localized: "PLAY")
        case .more: String(localized: "MORE")
        }
    }
}
