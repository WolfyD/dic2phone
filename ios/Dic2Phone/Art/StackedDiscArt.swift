import SwiftUI

/// A MiniDisc lying in a stack, seen from above: the coloured shell, and along its lower edge the
/// gold disc showing through the slot beside the metal shutter. The label is laid over it as a view.
struct StackedDiscArt {
    static let outline = MiniDiscOutline(cut: 16, corner: 16 * 0.35)
    /// How far the shine reaches down from the top edge: across the part of the disc the stack shows.
    private static let glossDepth: CGFloat = 30
    private static let gold = Gradient(colors: [Color(hex: 0xFFE27A), Color(hex: 0xE0A91E), Color(hex: 0xB9860F)])

    let shell: Color
    let edge: Color
    let edgeWidth: CGFloat

    func draw(in context: GraphicsContext, size: CGSize) {
        let outline = Self.outline.path(in: CGRect(origin: .zero, size: size))
        drawShell(outline, in: context, size: size)
        let slot = CGRect(x: size.width * 0.07, y: size.height * 0.62, width: size.width * 0.53, height: size.height * 0.38 - 10)
        context.fill(Path(roundedRect: slot, cornerRadius: 4), with: .color(.black.opacity(0.6)))
        drawDisc(in: context, slot: slot)
        drawShutter(in: context, slot: slot)
    }

    private func drawShell(_ outline: Path, in context: GraphicsContext, size: CGSize) {
        context.fill(outline, with: .linearGradient(
            Gradient(colors: [shell.mix(with: .white, by: 0.18), shell, shell.mix(with: .black, by: 0.35)]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height)
        ))
        context.fill(outline, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.22), .white.opacity(0)]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: Self.glossDepth)
        ))
        context.stroke(outline, with: .color(edge), lineWidth: edgeWidth)
    }

    private func drawDisc(in context: GraphicsContext, slot: CGRect) {
        var behindSlot = context
        behindSlot.clip(to: Path(slot))
        let center = CGPoint(x: slot.minX + slot.width * 0.72, y: slot.minY - slot.height * 0.1)
        let radius = slot.height
        behindSlot.fill(
            Path.circle(center: center, radius: radius),
            with: .radialGradient(Self.gold, center: center, startRadius: 0, endRadius: radius)
        )
        behindSlot.stroke(Path.circle(center: center, radius: radius * 0.32), with: .color(.black.opacity(0.25)), lineWidth: 1.5)
    }

    private func drawShutter(in context: GraphicsContext, slot: CGRect) {
        let shutter = CGRect(x: slot.minX - 2, y: slot.minY - 3, width: slot.width * 0.52 + 2, height: slot.height + 6)
        context.fill(Path(roundedRect: shutter, cornerRadius: 3), with: .linearGradient(
            MiniDiscArt.shutterMetal,
            startPoint: CGPoint(x: 0, y: slot.minY),
            endPoint: CGPoint(x: 0, y: slot.maxY)
        ))
        for grip in 1...3 {
            let y = slot.minY + slot.height * (0.25 + CGFloat(grip) * 0.1)
            let line = Path.line(
                from: CGPoint(x: shutter.minX + 8, y: y),
                to: CGPoint(x: shutter.minX + shutter.width * 0.55, y: y)
            )
            context.stroke(line, with: .color(.black.opacity(0.2)), lineWidth: 1.5)
        }
    }
}
