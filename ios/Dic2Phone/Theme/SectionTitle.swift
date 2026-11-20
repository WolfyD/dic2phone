import SwiftUI

/// A screen's heading, with the label stripes after it.
struct SectionTitle: View {
    let text: String

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: text)
                .font(DeckFont.monoBold.fixed(18))
                .tracking(2)
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            LabelStripes()
                .frame(width: 42, height: 4)
        }
    }
}
