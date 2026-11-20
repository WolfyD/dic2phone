import SwiftUI

/// The maker's badge across the top of the deck.
struct BrandPlate: View {
    @Environment(Settings.self) private var settings
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                stripes(palette.stripes)
                Text(verbatim: "DIC2PHONE")
                    .font(DeckFont.brand.fixed(26))
                    .tracking(3)
                    .foregroundStyle(LinearGradient(
                        colors: [palette.brand1, palette.brand2, palette.brand1, palette.brand2],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 12)
                stripes(palette.stripes.reversed())
            }
            Text(verbatim: settings.minidisc ? "STEREO MINIDISC RECORDER  DX-2" : "STEREO CASSETTE RECORDER  DX-2")
                .font(DeckFont.mono.fixed(10))
                .tracking(1)
                .foregroundStyle(palette.dim)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Dic2Phone"))
        .accessibilityAddTraits(.isHeader)
    }

    /// The logo keeps its size; the stripes either side give way when the plate is narrow.
    private func stripes(_ colors: [Color]) -> some View {
        HStack(spacing: 0) {
            ForEach(colors.indices, id: \.self) { index in
                colors[index].frame(height: 4)
            }
        }
        .frame(maxWidth: 54)
    }
}
