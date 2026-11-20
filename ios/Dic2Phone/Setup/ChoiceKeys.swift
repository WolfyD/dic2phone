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

extension ChoiceKeys {
    /// A choice of a number of days, where 0 is OFF; `onChoose` is given the days.
    init(days choices: [Int], chosen days: Int, onChoose: @escaping (Int) -> Void) {
        labels = choices.map { $0 == 0 ? String(localized: "OFF") : String(localized: "\($0)D") }
        chosen = choices.firstIndex(of: days) ?? 0
        self.onChoose = { onChoose(choices[$0]) }
    }
}
