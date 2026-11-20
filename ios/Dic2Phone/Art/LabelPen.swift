import SwiftUI

/// Writes the user's own words on a label, by hand or on a typewriter. Every letter is a little
/// off, seeded from the text so the writing doesn't jitter on each redraw.
enum LabelPen {
    /// A black fineliner on light labels, a silver paint pen on dark ones.
    static func ink(on label: Color) -> Color {
        label.luminance > 0.4 ? Color(hex: 0x15161C) : Color(hex: 0xE6E2D8)
    }

    /// - Parameter sizes: the handwriting sizes; typing uses smaller ones, as typewriter letters
    ///   are wider.
    static func write(
        _ text: String,
        on line: RuledLine,
        sizes: ClosedRange<CGFloat>,
        typed: Bool,
        ink: Color,
        in context: GraphicsContext
    ) {
        if typed {
            type(text, on: line, sizes: sizes.lowerBound * 0.68...sizes.upperBound * 0.62, ink: ink, in: context)
        } else {
            scrawl(text, on: line, sizes: sizes, ink: ink, in: context)
        }
    }

    /// The line slightly askew, every letter a little off in size, height, tilt and ink.
    private static func scrawl(_ text: String, on line: RuledLine, sizes: ClosedRange<CGFloat>, ink: Color, in context: GraphicsContext) {
        let fitted = ArtText.fitted(text, font: .hand, sizes: sizes, maxWidth: line.width * 0.97, color: ink, in: context)
        let size = fitted.size
        var random = SeededRandom(text: fitted.string)
        let baseline = line.y - size * 0.10
        var page = context
        page.rotate(by: .degrees(-1.6 + random.fraction() * 1.4), around: CGPoint(x: line.x, y: baseline))
        var x = line.x
        for letter in fitted.string {
            let glyph = String(letter)
            let advance = ArtText(glyph, font: .hand, size: size, color: ink, in: page).width
            let letterSize = size * (0.93 + random.fraction() * 0.14)
            let opacity = (205 + random.fraction() * 50) / 255
            let rise = (random.fraction() - 0.5) * size * 0.08
            var pen = page
            pen.rotate(by: .degrees((random.fraction() - 0.5) * 7), around: CGPoint(x: x + advance / 2, y: baseline))
            ArtText(glyph, font: .hand, size: letterSize, color: ink.opacity(opacity), in: pen)
                .draw(in: pen, x: x, baseline: baseline + rise)
            x += advance
        }
    }

    /// A straight line, but each letter struck a little harder or softer and a hair above or
    /// below it, and now and then struck twice.
    private static func type(_ text: String, on line: RuledLine, sizes: ClosedRange<CGFloat>, ink: Color, in context: GraphicsContext) {
        let fitted = ArtText.fitted(text, font: .mono, sizes: sizes, maxWidth: line.width, color: ink, in: context)
        let size = fitted.size
        var random = SeededRandom(text: fitted.string)
        let baseline = line.y - fitted.descent * 0.6
        var x = line.x
        for letter in fitted.string {
            let glyph = String(letter)
            let opacity = (150 + random.fraction() * 105) / 255
            let rise = (random.fraction() - 0.5) * size * 0.07
            let strike = ArtText(glyph, font: .mono, size: size, color: ink.opacity(opacity), in: context)
            strike.draw(in: context, x: x, baseline: baseline + rise)
            if random.fraction() < 0.2 {
                ArtText(glyph, font: .mono, size: size, color: ink.opacity(60.0 / 255), in: context)
                    .draw(in: context, x: x + size * 0.02, baseline: baseline + rise)
            }
            x += strike.width
        }
    }
}
