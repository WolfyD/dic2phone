import SwiftUI

/// What a rack is made of: wood for the shelf, steel for the vault.
enum RackMaterial {
    case wood
    case steel

    var side: [Color] {
        switch self {
        case .wood: [Color(hex: 0x5A3A22), Color(hex: 0x7A5232), Color(hex: 0x5A3A22)]
        case .steel: [Color(hex: 0x5E646B), Color(hex: 0xB4BAC0), Color(hex: 0x5E646B)]
        }
    }

    var back: Color {
        switch self {
        case .wood: Color(hex: 0x24170D)
        case .steel: Color(hex: 0x1B1E22)
        }
    }

    var frame: Color {
        switch self {
        case .wood: Color(hex: 0x3E2716)
        case .steel: Steel.edge
        }
    }
}
