import SwiftUI

/// A row of keys where exactly one is chosen, marked with a dot.
struct ChoiceKeys: View {
    let labels: [String]
    let chosen: Int
    let onChoose: (Int) -> Void

    var body: some View {
        WeightedRow(spacing: 6) {
            ForEach(labels.indices, id: \.self) { index in
                DeckKey(label: marked(index), height: 40) { onChoose(index) }
                    .accessibilityLabel(Text(verbatim: labels[index]))
                    .accessibilityAddTraits(index == chosen ? .isSelected : [])
            }
        }
    }

    private func marked(_ index: Int) -> String {
        index == chosen ? "\(Glyph.chosen) \(labels[index])" : labels[index]
    }
}
