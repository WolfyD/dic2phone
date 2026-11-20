import SwiftUI

/// The theme's backdrop behind every screen: a gradient, and on the synthwave theme a
/// perspective grid running to a setting sun.
struct DeckBackground: View {
    private static let gridLineWidth: CGFloat = 0.75
    private static let sunTop = Color(hex: 0xFFD319)
    private static let sunBottom = Color(hex: 0xFF2975)

    let palette: Palette

    var body: some View {
        let palette = palette
        Canvas { context, size in
            let screen = Path(CGRect(origin: .zero, size: size))
            context.fill(screen, with: .linearGradient(
                Gradient(colors: [palette.bgTop, palette.bgBottom]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            ))
            if let grid = palette.grid {
                Self.drawGrid(in: context, size: size, color: grid.opacity(0.35))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// Covers the lower 40%: lines spreading out from the middle of the horizon, and rungs
    /// coming closer together towards it.
    private static func drawGrid(in context: GraphicsContext, size: CGSize, color: Color) {
        let horizon = size.height * 0.6
        let middle = size.width / 2
        var lines = Path.line(from: CGPoint(x: 0, y: horizon), to: CGPoint(x: size.width, y: horizon))
        var gap: CGFloat = 2
        while horizon + gap < size.height {
            lines.addPath(.line(from: CGPoint(x: 0, y: horizon + gap), to: CGPoint(x: size.width, y: horizon + gap)))
            gap *= 1.35
        }
        for step in -12...12 {
            let spread = CGFloat(step)
            lines.addPath(.line(
                from: CGPoint(x: middle + spread * size.width * 0.02, y: horizon),
                to: CGPoint(x: middle + spread * size.width * 0.35, y: size.height)
            ))
        }
        context.stroke(lines, with: .color(color), lineWidth: gridLineWidth)

        let sunRadius = size.width * 0.3
        var sky = context
        sky.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: horizon)))
        sky.opacity = 70.0 / 255
        sky.fill(Path.circle(center: CGPoint(x: middle, y: horizon), radius: sunRadius), with: .linearGradient(
            Gradient(colors: [sunTop, sunBottom]),
            startPoint: CGPoint(x: 0, y: horizon - sunRadius),
            endPoint: CGPoint(x: 0, y: horizon)
        ))
    }
}
