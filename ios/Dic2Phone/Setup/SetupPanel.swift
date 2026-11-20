import SwiftUI

/// A titled group of settings on Setup.
struct SetupPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: title)
                .font(DeckFont.monoBold.fixed(15))
                .foregroundStyle(palette.text)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 8))
    }
}
