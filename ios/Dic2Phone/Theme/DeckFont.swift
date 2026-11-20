import SwiftUI

/// The bundled typefaces, so the deck looks the same on every phone. Symbols they lack
/// (▶ ⚑ ⏏) fall back to the system font by themselves.
enum DeckFont: String {
    case mono = "CourierPrime-Regular"
    case monoBold = "CourierPrime-Bold"
    case brand = "Barlow-BlackItalic"
    case badge = "Barlow-Bold"
    case hand = "ReenieBeanie"

    /// For text in the layout: grows with the user's text size.
    func size(_ points: CGFloat) -> Font {
        .custom(rawValue, size: points)
    }

    /// For text that's part of a drawing or a fixed-size instrument, scaled with it instead.
    func fixed(_ points: CGFloat) -> Font {
        .custom(rawValue, fixedSize: points)
    }
}
