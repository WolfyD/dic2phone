import SwiftUI

/// Little pictures printed on keys, where a glyph would say less.
enum KeyIcon {
    /// A stack of three cassette cases.
    case tapes
    /// Tapes standing on a shelf, the last one leaning.
    case shelf

    func draw(in context: GraphicsContext, size: CGSize, color: Color) {
        switch self {
        case .tapes: drawTapes(in: context, size: size, color: color)
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
