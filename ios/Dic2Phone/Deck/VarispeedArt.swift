import SwiftUI

/// Draws the varispeed: the slot, a notch per speed with the speed printed under it, and the
/// ridged knob.
struct VarispeedArt {
    private static let slotY: CGFloat = 15
    private static let slotHeight: CGFloat = 6
    private static let knobSize = CGSize(width: 18, height: 24)

    let knob: CGFloat
    let chosen: Int
    let speeds: [Float]
    let palette: Palette

    func draw(in context: GraphicsContext, size: CGSize, notches: FaderNotches) {
        drawSlot(in: context, size: size)
        for index in speeds.indices {
            drawNotch(index, in: context, size: size, notches: notches)
        }
        drawKnob(at: notches.x(of: knob), in: context)
    }

    private func drawSlot(in context: GraphicsContext, size: CGSize) {
        let slot = CGRect(
            x: FaderNotches.inset - 6,
            y: Self.slotY - Self.slotHeight / 2,
            width: size.width - 2 * FaderNotches.inset + 12,
            height: Self.slotHeight
        )
        context.fill(Path(roundedRect: slot, cornerRadius: Self.slotHeight / 2), with: .color(.black))
        let shine = CGRect(x: slot.minX, y: slot.maxY - 1, width: slot.width, height: 1)
        context.fill(Path(shine), with: .color(.white.opacity(0.12)))
    }

    private func drawNotch(_ index: Int, in context: GraphicsContext, size: CGSize, notches: FaderNotches) {
        let x = notches.x(of: CGFloat(index))
        let isChosen = index == chosen
        let color = isChosen ? palette.accent : palette.dim
        // The 1× notch, as recorded, gets the longer mark.
        let tick: CGFloat = speeds[index] == 1 ? 7 : 4
        context.fill(Path(CGRect(x: x - 1, y: Self.slotY + 6, width: 2, height: tick)), with: .color(color))

        let printed = Self.mark(speeds[index]) + (index == speeds.count - 1 ? "×" : "")
        let text = context.resolve(
            Text(verbatim: printed)
                .font(isChosen ? DeckFont.monoBold.fixed(11) : DeckFont.mono.fixed(11))
                .foregroundStyle(color)
        )
        let width = text.measure(in: size).width
        let left = min(max(x - width / 2, 0), size.width - width)
        context.draw(text, at: CGPoint(x: left, y: size.height), anchor: .bottomLeading)
    }

    private func drawKnob(at x: CGFloat, in context: GraphicsContext) {
        let size = Self.knobSize
        let cap = CGRect(x: x - size.width / 2, y: Self.slotY - size.height / 2, width: size.width, height: size.height)
        let shape = Path(roundedRect: cap, cornerRadius: 3)
        context.fill(shape.offsetBy(dx: 1, dy: 2), with: .color(.black.opacity(0.45)))
        context.fill(shape, with: .linearGradient(
            Gradient(colors: [palette.key1, palette.key2, palette.key2.mix(with: .black, by: 0.35)]),
            startPoint: CGPoint(x: 0, y: cap.minY),
            endPoint: CGPoint(x: 0, y: cap.maxY)
        ))
        context.stroke(shape, with: .color(.black.opacity(0.55)), lineWidth: 1)
        for ridge: CGFloat in [-7, -4, 4, 7] {
            let line = CGRect(x: cap.minX + 3, y: Self.slotY + ridge, width: size.width - 6, height: 1)
            context.fill(Path(line), with: .color(.black.opacity(0.28)))
        }
        let marker = CGRect(x: x - 1, y: cap.minY + 3, width: 2, height: size.height - 6)
        context.fill(Path(marker), with: .color(palette.accent))
    }

    /// The speed as printed under its notch.
    static func mark(_ speed: Float) -> String {
        switch speed {
        case 0.75: "¾"
        case 1.25: "1¼"
        case 1.5: "1½"
        default: speed.formatted()
        }
    }
}
