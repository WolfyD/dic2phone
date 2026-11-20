import SwiftUI

/// The name of one setting inside a panel.
struct SetupHeading: View {
    let text: String

    @Environment(\.palette) private var palette

    var body: some View {
        Text(verbatim: text)
            .font(DeckFont.monoBold.fixed(13))
            .foregroundStyle(palette.text)
    }
}
