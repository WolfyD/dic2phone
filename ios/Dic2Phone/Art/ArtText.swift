import SwiftUI

/// One line of text resolved for drawing into the artwork. It's placed by its baseline, like
/// Android's `drawText`, which the drawings were designed with.
struct ArtText {
    let string: String
    let size: CGFloat
    let width: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    private let resolved: GraphicsContext.ResolvedText

    /// Large enough never to wrap a single line.
    private static let unbounded = CGSize(width: 100_000, height: 100_000)

    init(_ string: String, font: DeckFont, size: CGFloat, color: Color, in context: GraphicsContext) {
        self.string = string
        self.size = size
        resolved = context.resolve(Text(verbatim: string).font(font.fixed(size)).foregroundStyle(color))
        let box = resolved.measure(in: Self.unbounded)
        width = box.width
        ascent = resolved.firstBaseline(in: Self.unbounded)
        descent = box.height - ascent
    }

    /// At the largest size from `sizes` that fits `maxWidth`, cut short with "…" if even the
    /// smallest is too wide.
    static func fitted(
        _ string: String,
        font: DeckFont,
        sizes: ClosedRange<CGFloat>,
        maxWidth: CGFloat,
        color: Color,
        in context: GraphicsContext
    ) -> ArtText {
        let largest = ArtText(string, font: font, size: sizes.upperBound, color: color, in: context)
        guard largest.width > maxWidth else { return largest }
        let size = max(sizes.lowerBound, sizes.upperBound * maxWidth / largest.width)
        return ellipsized(string, font: font, size: size, maxWidth: maxWidth, color: color, in: context)
    }

    static func ellipsized(
        _ string: String,
        font: DeckFont,
        size: CGFloat,
        maxWidth: CGFloat,
        color: Color,
        in context: GraphicsContext
    ) -> ArtText {
        var text = ArtText(string, font: font, size: size, color: color, in: context)
        var kept = string
        while text.width > maxWidth, !kept.isEmpty {
            kept.removeLast()
            text = ArtText(kept + "…", font: font, size: size, color: color, in: context)
        }
        return text
    }

    func draw(in context: GraphicsContext, x: CGFloat, baseline: CGFloat) {
        context.draw(resolved, at: CGPoint(x: x, y: baseline - ascent), anchor: .topLeading)
    }

    func drawCentered(in context: GraphicsContext, x: CGFloat, baseline: CGFloat) {
        draw(in: context, x: x - width / 2, baseline: baseline)
    }

    /// The baseline that centres the letters vertically on `y`.
    func baseline(centeredOn y: CGFloat) -> CGFloat {
        y + (ascent - descent) / 2
    }
}
