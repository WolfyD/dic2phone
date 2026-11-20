import SwiftUI

/// A dark strip holding a row of keys, sharing the width by each key's `layoutWeight`.
struct KeyRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        WeightedRow(spacing: 6) {
            content
        }
        .padding(6)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }
}
