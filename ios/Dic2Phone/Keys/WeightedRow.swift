import SwiftUI

/// A row that shares its width out by each view's `layoutWeight`, so a key and its printed label
/// line up across two rows.
struct WeightedRow: Layout {
    var spacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let widths = columnWidths(in: width, for: subviews)
        let height = zip(subviews, widths)
            .map { subview, columnWidth in
                subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: proposal.height)).height
            }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, columnWidth) in zip(subviews, columnWidths(in: bounds.width, for: subviews)) {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: columnWidth, height: bounds.height)
            )
            x += columnWidth + spacing
        }
    }

    private func columnWidths(in width: CGFloat, for subviews: Subviews) -> [CGFloat] {
        let weights = subviews.map { $0[LayoutWeight.self] }
        let total = weights.reduce(0, +)
        guard total > 0 else { return weights.map { _ in 0 } }
        let shared = max(width - spacing * CGFloat(max(subviews.count - 1, 0)), 0)
        return weights.map { shared * $0 / total }
    }
}
