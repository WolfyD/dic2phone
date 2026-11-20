import SwiftUI

/// A view's share of a `WeightedRow`'s width.
struct LayoutWeight: LayoutValueKey {
    static let defaultValue: CGFloat = 1
}

extension View {
    func layoutWeight(_ weight: CGFloat) -> some View {
        layoutValue(key: LayoutWeight.self, value: weight)
    }
}
