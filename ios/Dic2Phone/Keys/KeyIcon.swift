import SwiftUI

/// Little pictures printed on keys, where a glyph would say less.
enum KeyIcon {
    /// A stack of three cassette cases.
    case tapes
    /// Three MiniDiscs fanned out in a stack, the front one showing its label and shutter.
    case discs
    /// Tapes standing on a shelf, the last one leaning.
    case shelf

    func draw(in context: GraphicsContext, size: CGSize, color: Color) {
        switch self {
        case .tapes: drawTapes(in: context, size: size, color: color)
        case .discs: drawDiscs(in: context, size: size, color: color)
        case .shelf: drawShelf(in: context, size: size, color: color)
        }
    }

    private func drawTapes(in context: GraphicsContext, size: CGSize, color: Color) {
        let w = size.width
        let h = size.height
        let caseHeight = h * 0.24
        let gap = h * 0.1
        for index in 0..<3 {
            let y = h - CGFloat(index + 1) * caseHeight - CGFloat(index) * gap
            let inset = index == 1 ? w * 0.1 : 0
            let box = CGRect(x: inset, y: y, width: w - w * 0.1, height: caseHeight)
            context.stroke(Path(roundedRect: box, cornerRadius: h * 0.04), with: .color(color), lineWidth: h * 0.07)
            let window = CGRect(x: inset + w * 0.12, y: y + caseHeight * 0.3, width: w * 0.32, height: caseHeight * 0.4)
            context.fill(Path(window), with: .color(color))
        }
    }

    private func drawDiscs(in context: GraphicsContext, size: CGSize, color: Color) {
        let h = size.height
        let side = h * 0.66
        let back = CGRect(x: size.width - side, y: 0, width: side, height: side)
        let middle = CGRect(x: (size.width - side) / 2, y: (h - side) / 2, width: side, height: side)
        let front = CGRect(x: 0, y: h - side, width: side, height: side)
        let air = h * 0.08
        // Each disc hides the ones behind it, with a little air around its edge.
        var behindFront = context
        behindFront.clip(to: Path(front.insetBy(dx: -air, dy: -air)), options: .inverse)
        var behindMiddle = behindFront
        behindMiddle.clip(to: Path(middle.insetBy(dx: -air, dy: -air)), options: .inverse)
        let lineWidth = h * 0.07
        behindMiddle.stroke(Self.disc(in: back), with: .color(color), lineWidth: lineWidth)
        behindFront.stroke(Self.disc(in: middle), with: .color(color), lineWidth: lineWidth)
        context.stroke(Self.disc(in: front), with: .color(color), lineWidth: lineWidth)
        let label = CGRect(x: front.minX + side * 0.16, y: front.minY + side * 0.14, width: side * 0.68, height: side * 0.2)
        context.fill(Path(label), with: .color(color))
        let shutter = CGRect(x: front.minX + side * 0.14, y: front.minY + side * 0.52, width: side * 0.5, height: side * 0.34)
        context.stroke(Path(shutter), with: .color(color), lineWidth: h * 0.05)
    }

    /// A square with its top-left corner cut off.
    private static func disc(in box: CGRect) -> Path {
        let cut = box.width * 0.16
        var path = Path()
        path.addLines([
            CGPoint(x: box.minX + cut, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
            CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY),
            CGPoint(x: box.minX, y: box.minY + cut),
        ])
        path.closeSubpath()
        return path
    }

    private func drawShelf(in context: GraphicsContext, size: CGSize, color: Color) {
        let w = size.width
        let h = size.height
        let board = h * 0.1
        context.fill(Path(CGRect(x: 0, y: h - board, width: w, height: board)), with: .color(color))
        let spineWidth = w * 0.13
        let gap = w * 0.045
        for index in 0..<4 {
            let x = w * 0.04 + CGFloat(index) * (spineWidth + gap)
            context.fill(Path(CGRect(x: x, y: h * 0.12, width: spineWidth, height: h * 0.78)), with: .color(color))
        }
        var leaning = context
        leaning.rotate(by: .degrees(18), around: CGPoint(x: w * 0.96, y: h - board))
        leaning.fill(Path(CGRect(x: w * 0.96 - spineWidth, y: h * 0.12, width: spineWidth, height: h * 0.78)), with: .color(color))
    }
}
