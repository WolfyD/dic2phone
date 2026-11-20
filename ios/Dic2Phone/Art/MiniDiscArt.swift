import SwiftUI

/// A MiniDisc, drawn into a box `ratio` times as wide as it is tall: the label on top, the metal
/// shutter below. While open, the shutter is slid aside and the disc turns in the slot.
struct MiniDiscArt {
    /// A MiniDisc is 68 × 72 mm.
    static let ratio: CGFloat = 68.0 / 72.0

    /// The rainbow sheen of the disc's data side. Turning it is what shows the disc spinning.
    private static let sheen = Gradient(colors: [
        .white.opacity(0.25), .white.opacity(0.06), Color(hex: 0x66CCFF).opacity(0.2),
        .white.opacity(0.06), Color(hex: 0xFF66CC).opacity(0.19), .white.opacity(0.06),
        Color(hex: 0xFFE066).opacity(0.22), .white.opacity(0.06), .white.opacity(0.25),
    ])
    private static let shutterMetal = Gradient(colors: [
        Color(hex: 0xE4E6E9), Color(hex: 0xA9ADB3), Color(hex: 0xCDD0D4), Color(hex: 0x8C9096),
    ])

    let palette: Palette
    let label: CassetteLabel
    /// The user's writing is typed instead of handwritten.
    let typed: Bool
    /// The deck's reel angle; the disc turns three times as fast.
    let reelAngle: Angle
    let open: Bool

    func draw(in context: GraphicsContext, width: CGFloat) {
        let size = CGSize(width: width, height: width / Self.ratio)
        let outline = Self.outline(size)
        drawShell(outline, in: context, size: size)
        drawLabel(in: context, size: size)
        let slot = CGRect(x: width * 0.08, y: size.height * 0.53, width: width * 0.68, height: size.height * 0.40)
        context.fill(Path(roundedRect: slot, cornerRadius: width * 0.015), with: .color(.black.opacity(0.55)))
        if open {
            drawDisc(in: context, size: size, slot: slot)
        }
        var underShell = context
        underShell.clip(to: outline)
        drawShutter(in: underShell, size: size, slot: slot)
        drawWriteProtect(in: context, size: size)
        drawLength(in: context, size: size)
    }

    /// Rounded corners, but for the top-left one cut off square.
    private static func outline(_ size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        let corner = w * 0.04
        let cut = w * 0.08
        var path = Path()
        path.move(to: CGPoint(x: cut, y: 0))
        path.addLine(to: CGPoint(x: w - corner, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: corner), control: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: h - corner))
        path.addQuadCurve(to: CGPoint(x: w - corner, y: h), control: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: corner, y: h))
        path.addQuadCurve(to: CGPoint(x: 0, y: h - corner), control: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: cut))
        path.closeSubpath()
        return path
    }

    private func drawShell(_ outline: Path, in context: GraphicsContext, size: CGSize) {
        context.fill(outline, with: .linearGradient(
            Gradient(colors: [palette.shell1, palette.shell2]),
            startPoint: .zero,
            endPoint: CGPoint(x: size.width, y: size.height)
        ))
        context.fill(outline, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.10), .white.opacity(0)]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height * 0.3)
        ))
        context.stroke(outline, with: .color(.white.opacity(0.12)), lineWidth: size.width * 0.008)
    }

    private func drawLabel(in context: GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let paper = CGRect(x: w * 0.08, y: h * 0.07, width: w * 0.84, height: h * 0.40)
        context.fill(Path(roundedRect: paper, cornerRadius: w * 0.02), with: .color(palette.label))
        let bandHeight = paper.height * 0.16
        let band = CGRect(x: paper.minX, y: paper.maxY - bandHeight - paper.height * 0.06, width: paper.width, height: bandHeight)
        context.fillStripes(palette.stripes, in: band)

        let textX = paper.minX + paper.width * 0.06
        let textWidth = paper.width * 0.88
        let titleLine = RuledLine(x: textX, y: paper.minY + paper.height * 0.40, width: textWidth)
        let subtitleLine = RuledLine(x: textX, y: paper.minY + paper.height * 0.66, width: textWidth)
        for line in [titleLine, subtitleLine] {
            line.draw(in: context, color: palette.ink.opacity(0.35), lineWidth: w * 0.0025)
        }
        drawTitle(in: context, on: titleLine, size: size)
        let subtitle = ArtText.fitted(
            label.subtitle, font: .mono, sizes: h * 0.038...h * 0.05, maxWidth: textWidth, color: palette.ink.opacity(0.8), in: context
        )
        subtitle.draw(in: context, x: textX, baseline: subtitleLine.y - subtitle.descent - w * 0.002)
        drawInsertArrow(in: context, size: size, above: paper)
    }

    private func drawTitle(in context: GraphicsContext, on line: RuledLine, size: CGSize) {
        let h = size.height
        if label.handwritten {
            LabelPen.write(
                label.title, on: line, sizes: h * 0.075...h * 0.13, typed: typed,
                ink: LabelPen.ink(on: palette.label), in: context
            )
        } else {
            let title = ArtText.fitted(
                label.title, font: .monoBold, sizes: h * 0.05...h * 0.085, maxWidth: line.width, color: palette.ink, in: context
            )
            title.draw(in: context, x: line.x, baseline: line.y - title.descent - size.width * 0.002)
        }
    }

    /// The little triangle that shows which way the disc goes in.
    private func drawInsertArrow(in context: GraphicsContext, size: CGSize, above paper: CGRect) {
        let tip = CGPoint(x: paper.midX, y: paper.minY * 0.5 - size.height * 0.018)
        let baseY = paper.minY * 0.5 + size.height * 0.015
        var arrow = Path()
        arrow.addLines([
            tip,
            CGPoint(x: tip.x + size.width * 0.03, y: baseY),
            CGPoint(x: tip.x - size.width * 0.03, y: baseY),
        ])
        arrow.closeSubpath()
        context.fill(arrow, with: .color(.white.opacity(0.35)))
    }

    private func drawDisc(in context: GraphicsContext, size: CGSize, slot: CGRect) {
        var behindSlot = context
        behindSlot.clip(to: Path(roundedRect: slot, cornerRadius: size.width * 0.015))
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let radius = size.width * 0.47
        behindSlot.fill(Path.circle(center: center, radius: radius), with: .color(palette.window))
        let surface = Path.circle(center: center, radius: radius * 0.97)
        let turned = Angle.degrees(reelAngle.degrees * 3)
        behindSlot.fill(surface, with: .conicGradient(Self.sheen, center: center, angle: turned))
        for ring in [surface, Path.circle(center: center, radius: radius * 0.40)] {
            behindSlot.stroke(ring, with: .color(.white.opacity(0.25)), lineWidth: size.width * 0.006)
        }
    }

    /// Closed over the slot, or slid right and tucked under the edge of the shell.
    private func drawShutter(in context: GraphicsContext, size: CGSize, slot: CGRect) {
        let w = size.width
        let h = size.height
        let slide = open ? slot.width * 0.78 : 0
        let shutter = slot.offsetBy(dx: slide, dy: 0).insetBy(dx: -w * 0.01, dy: -h * 0.01)
        let plate = Path(roundedRect: shutter, cornerRadius: w * 0.015)
        context.fill(plate, with: .linearGradient(
            Self.shutterMetal,
            startPoint: CGPoint(x: 0, y: shutter.minY),
            endPoint: CGPoint(x: 0, y: shutter.maxY)
        ))
        for grip in 1...3 {
            let y = shutter.minY + shutter.height * (0.2 + CGFloat(grip) * 0.08)
            let line = Path.line(
                from: CGPoint(x: shutter.minX + shutter.width * 0.08, y: y),
                to: CGPoint(x: shutter.minX + shutter.width * 0.5, y: y)
            )
            context.stroke(line, with: .color(.black.opacity(0.18)), lineWidth: h * 0.006)
        }
        context.stroke(plate, with: .color(.black.opacity(0.4)), lineWidth: w * 0.005)
    }

    private func drawWriteProtect(in context: GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let notch = CGRect(x: w * 0.82, y: h * 0.56, width: w * 0.09, height: h * 0.08)
        context.fill(Path(roundedRect: notch, cornerRadius: w * 0.01), with: .color(.black.opacity(0.5)))
        let tab = CGRect(x: w * 0.83, y: h * 0.57, width: w * 0.03, height: h * 0.06)
        context.fill(Path(roundedRect: tab, cornerRadius: w * 0.005), with: .color(palette.hub.opacity(0.8)))
    }

    /// "74 MIN", as on the back corner of a blank disc.
    private func drawLength(in context: GraphicsContext, size: CGSize) {
        let x = size.width * 0.865
        let h = size.height
        ArtText("74", font: .monoBold, size: h * 0.055, color: .white.opacity(0.45), in: context)
            .drawCentered(in: context, x: x, baseline: h * 0.80)
        ArtText("MIN", font: .mono, size: h * 0.03, color: .white.opacity(0.45), in: context)
            .drawCentered(in: context, x: x, baseline: h * 0.85)
    }
}
