import SwiftUI

extension GraphicsContext {
    /// The label's coloured stripes, stacked top to bottom across `band`.
    func fillStripes(_ colors: [Color], in band: CGRect) {
        let stripeHeight = band.height / CGFloat(colors.count)
        for (index, color) in colors.enumerated() {
            // Overlapping by half a point leaves no hairline gaps between the stripes.
            let stripe = CGRect(x: band.minX, y: band.minY + CGFloat(index) * stripeHeight, width: band.width, height: stripeHeight + 0.5)
            fill(Path(stripe), with: .color(color))
        }
    }
}
