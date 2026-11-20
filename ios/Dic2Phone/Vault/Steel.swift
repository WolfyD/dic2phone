import SwiftUI

/// The vault's brushed steel, in the Android app's colours.
enum Steel {
    static let plate = LinearGradient(
        colors: [Color(hex: 0x9AA1A8), Color(hex: 0x5B6168), Color(hex: 0x7D848B)],
        startPoint: .top, endPoint: .bottom
    )
    static let ink = Color(hex: 0x15181B)
    static let edge = Color(hex: 0x3A3F45)
}
