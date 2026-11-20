import SwiftUI

/// The VU meter, drawn into a box `ratio` times as wide as it is tall: a lit window with the
/// scale across it and a needle riding left and right.
struct VuMeterArt {
    static let ratio: CGFloat = 5.6
    /// Where 0 dB sits on the scale; the red zone starts there.
    private static let zeroDecibels: CGFloat = 0.8
    private static let scaleLabels = [0: "-20", 2: "-10", 4: "-7", 6: "-3", 8: "0", 10: "+3"]

    let palette: Palette
    /// The needle's place on the scale, 0...1; a little past 1 pins it in the red.
    let needle: CGFloat

    func draw(in context: GraphicsContext, width w: CGFloat) {
        let h = w / Self.ratio
        context.fill(
            Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: h * 0.16),
            with: .color(Color(hex: 0x0E0C0A))
        )
        let inset = h * 0.09
        let face = CGRect(x: inset, y: inset, width: w - inset * 2, height: h - inset * 2)
        context.fill(Path(roundedRect: face, cornerRadius: h * 0.1), with: .linearGradient(
            Gradient(colors: [palette.vu1, palette.vu2]),
            startPoint: CGPoint(x: 0, y: face.minY),
            endPoint: CGPoint(x: 0, y: face.maxY)
        ))
        var window = context
        window.clip(to: Path(face))

        let badge = ArtText("VU", font: .monoBold, size: h * 0.34, color: palette.vuInk, in: window)
        let badgeX = inset + h * 0.22
        badge.draw(in: window, x: badgeX, baseline: badge.baseline(centeredOn: h / 2))
        let scale = Scale(start: badgeX + badge.width + h * 0.45, end: w - inset - h * 0.35, lineY: h * 0.56)
        drawScale(in: window, scale: scale, height: h)
        drawNeedle(in: window, at: scale.x(min(max(needle, 0), 1.05)), lineY: scale.lineY, height: h, inset: inset)
    }

    private struct Scale {
        let start: CGFloat
        let end: CGFloat
        let lineY: CGFloat

        func x(_ fraction: CGFloat) -> CGFloat {
            start + (end - start) * fraction
        }
    }

    private func drawScale(in context: GraphicsContext, scale: Scale, height h: CGFloat) {
        let red = scale.x(Self.zeroDecibels)
        context.stroke(
            Path.line(from: CGPoint(x: scale.start, y: scale.lineY), to: CGPoint(x: red, y: scale.lineY)),
            with: .color(palette.vuInk), style: StrokeStyle(lineWidth: h * 0.035, lineCap: .butt)
        )
        let redLineY = scale.lineY + h * 0.03
        context.stroke(
            Path.line(from: CGPoint(x: red, y: redLineY), to: CGPoint(x: scale.end, y: redLineY)),
            with: .color(palette.vuRed), style: StrokeStyle(lineWidth: h * 0.09, lineCap: .butt)
        )
        for step in 0...10 {
            let x = scale.x(CGFloat(step) / 10)
            let major = step.isMultiple(of: 2)
            let hot = step >= 8
            let color = hot ? palette.vuRed : palette.vuInk
            let tick = Path.line(from: CGPoint(x: x, y: scale.lineY), to: CGPoint(x: x, y: scale.lineY + h * (major ? 0.2 : 0.12)))
            context.stroke(tick, with: .color(color), style: StrokeStyle(lineWidth: h * (major ? 0.035 : 0.025), lineCap: .butt))
            if let text = Self.scaleLabels[step] {
                ArtText(text, font: hot ? .monoBold : .mono, size: h * 0.2, color: color, in: context)
                    .drawCentered(in: context, x: x, baseline: scale.lineY - h * 0.1)
            }
        }
    }

    /// A thin wire with a soft shadow on the face. It rides over the ticks only, under the
    /// numbers, so it never hides "-20" at rest.
    private func drawNeedle(in context: GraphicsContext, at x: CGFloat, lineY: CGFloat, height h: CGFloat, inset: CGFloat) {
        let top = lineY - h * 0.07
        let bottom = h - inset - h * 0.06
        let shadowX = x + h * 0.05
        context.stroke(
            Path.line(from: CGPoint(x: shadowX, y: top + h * 0.04), to: CGPoint(x: shadowX, y: bottom)),
            with: .color(.black.opacity(0.18)), style: StrokeStyle(lineWidth: h * 0.06, lineCap: .round)
        )
        context.stroke(
            Path.line(from: CGPoint(x: x, y: top), to: CGPoint(x: x, y: bottom)),
            with: .color(palette.vuInk), style: StrokeStyle(lineWidth: h * 0.04, lineCap: .round)
        )
    }
}
