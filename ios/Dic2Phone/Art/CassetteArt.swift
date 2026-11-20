import SwiftUI

/// The cassette, drawn into a box `ratio` times as wide as it is tall: shell, label, the window
/// with its reels, and the screws along the edge.
struct CassetteArt {
    static let ratio: CGFloat = 1.58

    let palette: Palette
    let label: CassetteLabel
    /// The user's writing is typed instead of handwritten.
    let typed: Bool
    let reelAngle: Angle
    /// How far the tape has wound from the left reel to the right, 0...1.
    let progress: CGFloat

    func draw(in context: GraphicsContext, width: CGFloat) {
        let size = CGSize(width: width, height: width / Self.ratio)
        drawShell(in: context, size: size)
        let band = drawLabel(in: context, size: size)
        drawWindow(in: context, size: size, band: band)
        drawBottom(in: context, size: size)
    }

    private func drawShell(in context: GraphicsContext, size: CGSize) {
        let shell = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.width * 0.035)
        context.fill(shell, with: .linearGradient(
            Gradient(colors: [palette.shell1, palette.shell2]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height)
        ))
        context.stroke(shell, with: .color(.white.opacity(0.08)), lineWidth: size.width * 0.006)
    }

    /// - Returns: the stripe band across the label, which the window sits in.
    private func drawLabel(in context: GraphicsContext, size: CGSize) -> CGRect {
        let w = size.width
        let h = size.height
        let paper = CGRect(x: w * 0.07, y: h * 0.07, width: w * 0.86, height: h * 0.64)
        context.fill(Path(roundedRect: paper, cornerRadius: w * 0.015), with: .color(palette.label))
        let band = CGRect(x: paper.minX, y: paper.minY + paper.height * 0.40, width: paper.width, height: paper.height * 0.52)
        drawStripes(in: context, band: band)

        let side = ArtText("A", font: .badge, size: h * 0.16, color: palette.ink, in: context)
        side.draw(in: context, x: paper.minX + paper.width * 0.025, baseline: paper.minY + paper.height * 0.01 + side.ascent)

        let textX = paper.minX + paper.width * 0.13
        let textWidth = paper.width * 0.83
        let titleLine = RuledLine(x: textX, y: paper.minY + paper.height * 0.22, width: textWidth)
        let subtitleLine = RuledLine(x: textX, y: paper.minY + paper.height * 0.36, width: textWidth)
        for line in [titleLine, subtitleLine] {
            let rule = Path.line(from: CGPoint(x: line.x, y: line.y), to: CGPoint(x: line.x + line.width, y: line.y))
            context.stroke(rule, with: .color(palette.ink.opacity(0.35)), lineWidth: w * 0.0015)
        }
        drawTitle(in: context, on: titleLine, size: size)
        let subtitle = ArtText.ellipsized(
            label.subtitle, font: .mono, size: h * 0.06, maxWidth: textWidth, color: palette.ink.opacity(0.8), in: context
        )
        subtitle.draw(in: context, x: textX, baseline: subtitleLine.y - subtitle.descent - w * 0.001)
        return band
    }

    private func drawStripes(in context: GraphicsContext, band: CGRect) {
        let stripeHeight = band.height / CGFloat(palette.stripes.count)
        for (index, color) in palette.stripes.enumerated() {
            // Overlapping by half a point leaves no hairline gaps between the stripes.
            let stripe = CGRect(x: band.minX, y: band.minY + CGFloat(index) * stripeHeight, width: band.width, height: stripeHeight + 0.5)
            context.fill(Path(stripe), with: .color(color))
        }
    }

    private func drawTitle(in context: GraphicsContext, on line: RuledLine, size: CGSize) {
        let h = size.height
        if label.handwritten {
            LabelPen.write(
                label.title, on: line, sizes: h * 0.085...h * 0.15, typed: typed,
                ink: LabelPen.ink(on: palette.label), in: context
            )
        } else {
            let title = ArtText.fitted(
                label.title, font: .monoBold, sizes: h * 0.052...h * 0.085, maxWidth: line.width, color: palette.ink, in: context
            )
            title.draw(in: context, x: line.x, baseline: line.y - title.descent - size.width * 0.001)
        }
    }

    private func drawWindow(in context: GraphicsContext, size: CGSize, band: CGRect) {
        let w = size.width
        let window = CGRect(x: w * 0.25, y: band.minY + band.height * 0.1, width: w * 0.5, height: band.height * 0.8)
        let outline = Path(roundedRect: window, cornerRadius: window.height * 0.25)
        context.fill(outline, with: .color(palette.window))
        let reels = [
            CGPoint(x: window.minX + window.width * 0.2, y: window.midY),
            CGPoint(x: window.minX + window.width * 0.8, y: window.midY),
        ]
        var inside = context
        inside.clip(to: outline)
        drawTapePacks(in: inside, reels: reels, windowHeight: window.height, lineWidth: w * 0.002)
        for reel in reels {
            drawHub(in: context, at: reel, radius: window.height * 0.28)
        }
        let glare = Path.line(
            from: CGPoint(x: window.minX + window.width * 0.35, y: window.minY - w * 0.004),
            to: CGPoint(x: window.minX + window.width * 0.2, y: window.maxY + w * 0.004)
        )
        inside.stroke(glare, with: .color(.white.opacity(0.10)), lineWidth: window.height * 0.25)
        context.stroke(outline, with: .color(.black.opacity(0.6)), lineWidth: w * 0.003)
    }

    /// The wound tape on each reel: the left one empties as the right one fills.
    private func drawTapePacks(in context: GraphicsContext, reels: [CGPoint], windowHeight: CGFloat, lineWidth: CGFloat) {
        let smallest = windowHeight * 0.32
        let largest = windowHeight * 0.95
        let wound = min(max(progress, 0), 1)
        let radii = [smallest + (largest - smallest) * (1 - wound), smallest + (largest - smallest) * wound]
        for (reel, radius) in zip(reels, radii) {
            let pack = Path.circle(center: reel, radius: radius)
            context.fill(pack, with: .color(palette.pack))
            context.stroke(pack, with: .color(.white.opacity(0.06)), lineWidth: lineWidth)
        }
    }

    private func drawHub(in context: GraphicsContext, at center: CGPoint, radius: CGFloat) {
        context.fill(Path.circle(center: center, radius: radius), with: .color(palette.hub))
        context.fill(Path.circle(center: center, radius: radius * 0.62), with: .color(palette.window))
        let tooth = CGRect(x: center.x - radius * 0.08, y: center.y - radius * 0.62, width: radius * 0.16, height: radius * 0.22)
        for index in 0..<6 {
            var turned = context
            turned.rotate(by: reelAngle + .degrees(Double(index) * 60), around: center)
            turned.fill(Path(tooth), with: .color(palette.hub))
        }
    }

    private func drawBottom(in context: GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        var ramp = Path()
        ramp.addLines([
            CGPoint(x: w * 0.2, y: h), CGPoint(x: w * 0.25, y: h * 0.78),
            CGPoint(x: w * 0.75, y: h * 0.78), CGPoint(x: w * 0.8, y: h),
        ])
        ramp.closeSubpath()
        context.fill(ramp, with: .color(.black.opacity(0.25)))
        for holeX in [w * 0.35, w * 0.65] {
            context.fill(Path.circle(center: CGPoint(x: holeX, y: h * 0.9), radius: h * 0.025), with: .color(.black))
        }
        let screws: [(CGFloat, CGFloat)] = [(0.035, 0.055), (0.965, 0.055), (0.035, 0.945), (0.965, 0.945), (0.5, 0.88)]
        for (sx, sy) in screws {
            let center = CGPoint(x: w * sx, y: h * sy)
            context.fill(Path.circle(center: center, radius: w * 0.012), with: .color(Color(hex: 0x8A8A8A)))
            let slot = Path.line(from: CGPoint(x: center.x - w * 0.008, y: center.y), to: CGPoint(x: center.x + w * 0.008, y: center.y))
            context.stroke(slot, with: .color(Color(hex: 0x3A3A3A)), lineWidth: w * 0.002)
        }
    }
}
