import SwiftUI

/// The tape's position bar: tap or drag to wind there. Flags are the red marks; a tap near one
/// jumps straight to it.
struct ScrubStrip: View {
    /// A tap this close to a flag lands on it: about a fingertip.
    private static let flagReach: CGFloat = 16
    private static let accessibilityStepMs: Int64 = 10_000

    let durationMs: Int64
    let positionMs: Int64
    let flags: [Int64]
    let onSeek: (Int64) -> Void
    let onFlag: (Int64) -> Void

    @Environment(\.palette) private var palette
    @GestureState private var dragFraction: CGFloat?

    private var length: CGFloat { CGFloat(max(durationMs, 1)) }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = dragFraction ?? min(max(CGFloat(positionMs) / length, 0), 1)
            let flagFractions = flags.map { min(max(CGFloat($0) / length, 0), 1) }
            let palette = palette
            Canvas { context, size in
                Self.draw(in: context, size: size, fraction: fraction, flags: flagFractions, palette: palette)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                tap(at: location.x, width: width)
            }
            .gesture(scrub(width: width))
        }
        .frame(height: 30)
        .accessibilityElement()
        .accessibilityLabel(Text("Tape position"))
        .accessibilityValue(Text(verbatim: "\(TapeNames.duration(ms: positionMs)) / \(TapeNames.duration(ms: durationMs))"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(positionMs + Self.accessibilityStepMs)
            case .decrement: onSeek(positionMs - Self.accessibilityStepMs)
            @unknown default: break
            }
        }
    }

    private func scrub(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragFraction) { drag, fraction, _ in
                fraction = Self.fraction(of: drag.location.x, in: width)
            }
            .onEnded { drag in
                onSeek(Int64(Self.fraction(of: drag.location.x, in: width) * length))
            }
    }

    private func tap(at x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let nearest = flags.min { abs(xOf($0, width) - x) < abs(xOf($1, width) - x) }
        if let nearest, abs(xOf(nearest, width) - x) <= Self.flagReach {
            onFlag(nearest)
        } else {
            onSeek(Int64(Self.fraction(of: x, in: width) * length))
        }
    }

    private func xOf(_ ms: Int64, _ width: CGFloat) -> CGFloat {
        CGFloat(ms) / length * width
    }

    private static func fraction(of x: CGFloat, in width: CGFloat) -> CGFloat {
        width > 0 ? min(max(x / width, 0), 1) : 0
    }

    private static func draw(in context: GraphicsContext, size: CGSize, fraction: CGFloat, flags: [CGFloat], palette: Palette) {
        let top = size.height * 0.42
        let thickness = size.height * 0.32
        let track = CGRect(x: 0, y: top, width: size.width, height: thickness)
        context.fill(Path(roundedRect: track, cornerRadius: thickness / 2), with: .color(.black))
        let wound = CGRect(x: 0, y: top, width: size.width * fraction, height: thickness)
        context.fill(Path(roundedRect: wound, cornerRadius: thickness / 2), with: .color(palette.accent))
        for flag in flags {
            let x = flag * size.width
            var pennant = Path()
            pennant.addLines([CGPoint(x: x - 6, y: 0), CGPoint(x: x + 6, y: 0), CGPoint(x: x, y: top - 2)])
            pennant.closeSubpath()
            context.fill(pennant, with: .color(palette.danger))
            context.fill(Path(CGRect(x: x - 1, y: top, width: 2, height: thickness)), with: .color(palette.danger))
        }
        let playhead = CGRect(x: fraction * size.width - 2, y: top - 3, width: 4, height: thickness + 6)
        context.fill(Path(playhead), with: .color(palette.text))
    }
}
