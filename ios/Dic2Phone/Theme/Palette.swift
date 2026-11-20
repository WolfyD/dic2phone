import SwiftUI

/// One complete look for the deck.
struct Palette: Identifiable, Sendable {
    let id: String
    let name: String
    let bgTop: Color
    let bgBottom: Color
    /// The synthwave perspective grid; other themes have none.
    var grid: Color?
    let panel: Color
    let text: Color
    let dim: Color
    let key1: Color
    let key2: Color
    let keyText: Color
    let brand1: Color
    let brand2: Color
    let label: Color
    let ink: Color
    let stripes: [Color]
    let shell1: Color
    let shell2: Color
    let window: Color
    let pack: Color
    let hub: Color
    let vu1: Color
    let vu2: Color
    let vuInk: Color
    let vuRed: Color
    let led: Color
    let ledOff: Color
    let accent: Color
    let danger: Color
    let counterBg: Color
    let counterDigit: Color
    let rec1: Color
    let rec2: Color

    /// Light themes get dark status-bar text.
    var isLight: Bool {
        bgTop.luminance > 0.5
    }
}
