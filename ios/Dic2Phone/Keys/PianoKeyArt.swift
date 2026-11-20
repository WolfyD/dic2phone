import SwiftUI

/// The drawing of a piano key at one point of its travel.
struct PianoKeyArt {
    let down: CGFloat
    let lip: CGFloat
    let travel: CGFloat
    let face1: Color
    let face2: Color

    func draw(in context: GraphicsContext, size: CGSize) {
        let top = travel * down
        let lipNow = lip * (1 - 0.7 * down)
        let face = CGRect(x: 0, y: top, width: size.width, height: size.height - lipNow - top)
        drawFace(in: context, face: face)
        let front = CGRect(x: 0, y: size.height - lipNow, width: size.width, height: lipNow)
        context.fill(Path(front), with: .linearGradient(
            Gradient(colors: [face2.mix(with: .black, by: 0.35), face2.mix(with: .black, by: 0.7)]),
            startPoint: CGPoint(x: 0, y: front.minY),
            endPoint: CGPoint(x: 0, y: front.maxY)
        ))
        context.fill(Path(CGRect(x: 0, y: front.minY, width: size.width, height: 1)), with: .color(.black.opacity(0.5)))
    }

    /// Lit from above, its sides rounding off into shade, and darker once it's down in the well.
    private func drawFace(in context: GraphicsContext, face: CGRect) {
        context.fill(Path(face), with: .linearGradient(
            Gradient(colors: [face1, face2]),
            startPoint: CGPoint(x: 0, y: face.minY),
            endPoint: CGPoint(x: 0, y: face.maxY)
        ))
        context.fill(Path(face), with: .linearGradient(
            Gradient(stops: [
                .init(color: .black.opacity(0.22), location: 0),
                .init(color: .clear, location: 0.07),
                .init(color: .clear, location: 0.93),
                .init(color: .black.opacity(0.3), location: 1),
            ]),
            startPoint: CGPoint(x: face.minX, y: 0),
            endPoint: CGPoint(x: face.maxX, y: 0)
        ))
        if down > 0 {
            context.fill(Path(face), with: .color(.black.opacity(0.16 * down)))
        }
        let highlight = CGRect(x: face.minX, y: face.minY, width: face.width, height: 1.5)
        context.fill(Path(highlight), with: .color(.white.opacity(0.45 * (1 - 0.6 * down))))
    }
}
