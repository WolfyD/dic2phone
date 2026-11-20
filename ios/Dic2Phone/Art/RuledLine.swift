import SwiftUI

/// A line printed on a label for writing on: where it starts, its height and its length.
struct RuledLine {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat

    func draw(in context: GraphicsContext, color: Color, lineWidth: CGFloat) {
        let rule = Path.line(from: CGPoint(x: x, y: y), to: CGPoint(x: x + width, y: y))
        context.stroke(rule, with: .color(color), lineWidth: lineWidth)
    }
}
