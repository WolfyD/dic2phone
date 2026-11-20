import SwiftUI

/// What a setting does, in small print.
struct SetupHelp: View {
    let text: String

    @Environment(\.palette) private var palette

    var body: some View {
        Text(verbatim: text)
            .font(DeckFont.mono.fixed(12))
            .foregroundStyle(palette.dim)
            .fixedSize(horizontal: false, vertical: true)
    }
}
