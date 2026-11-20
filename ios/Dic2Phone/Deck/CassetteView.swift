import SwiftUI

/// The cassette in the deck, its reels turning while the tape moves.
struct CassetteView: View {
    let label: CassetteLabel
    let spinning: Bool
    /// How far the tape has wound, 0...1.
    let progress: CGFloat
    /// The user's writing is typed instead of handwritten.
    let typed: Bool

    @Environment(\.palette) private var palette
    @State private var spin = ReelSpin()

    var body: some View {
        TimelineView(.animation(paused: !spinning)) { timeline in
            let art = CassetteArt(
                palette: palette, label: label, typed: typed,
                reelAngle: spin.angle(at: timeline.date), progress: progress
            )
            Canvas { context, size in
                art.draw(in: context, width: size.width)
            }
        }
        .aspectRatio(CassetteArt.ratio, contentMode: .fit)
        .onChange(of: spinning, initial: true) {
            spin.update(spinning: spinning)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: [label.title, label.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")))
    }
}
