import SwiftUI

/// The theme's coloured stripes, side by side, as printed on the cassette labels.
struct LabelStripes: View {
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            ForEach(palette.stripes.indices, id: \.self) { index in
                palette.stripes[index]
            }
        }
        .accessibilityHidden(true)
    }
}
