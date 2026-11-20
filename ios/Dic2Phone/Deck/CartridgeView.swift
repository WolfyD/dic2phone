import SwiftUI

/// What's in the deck: a cassette with its reels turning while the tape moves, or in MINIDISC
/// mode a MiniDisc, its shutter open and the disc spinning. The disc sits in the cassette's box,
/// so every layout fits either.
struct CartridgeView: View {
    let label: CassetteLabel
    let spinning: Bool
    /// How far the tape has wound, 0...1.
    let progress: CGFloat
    /// The user's writing is typed instead of handwritten.
    let typed: Bool

    @Environment(Settings.self) private var settings
    @Environment(\.palette) private var palette
    @State private var spin = ReelSpin()

    var body: some View {
        let minidisc = settings.minidisc
        TimelineView(.animation(paused: !spinning)) { timeline in
            let angle = spin.angle(at: timeline.date)
            Canvas { context, size in
                if minidisc {
                    drawDisc(turnedTo: angle, in: context, box: size)
                } else {
                    CassetteArt(palette: palette, label: label, typed: typed, reelAngle: angle, progress: progress)
                        .draw(in: context, width: size.width)
                }
            }
        }
        .aspectRatio(CassetteArt.ratio, contentMode: .fit)
        .onChange(of: spinning, initial: true) {
            spin.update(spinning: spinning)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: [label.title, label.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")))
    }

    private func drawDisc(turnedTo angle: Angle, in context: GraphicsContext, box: CGSize) {
        let height = box.height * 0.98
        let width = height * MiniDiscArt.ratio
        var centered = context
        centered.translateBy(x: (box.width - width) / 2, y: (box.height - height) / 2)
        MiniDiscArt(palette: palette, label: label, typed: typed, reelAngle: angle, open: spinning)
            .draw(in: centered, width: width)
    }
}
