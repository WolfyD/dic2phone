import SwiftUI

/// The play time in a little recessed display, like the counter's: position, length and the
/// number of flags. The digits light up while the tape plays.
struct TimeWindow: View {
    let positionMs: Int64
    let durationMs: Int64
    let flags: Int
    let playing: Bool

    @Environment(\.palette) private var palette

    var body: some View {
        let lit = playing ? palette.led : palette.counterDigit
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: TapeNames.duration(ms: positionMs))
                .font(DeckFont.monoBold.fixed(18))
                .foregroundStyle(lit)
            Text(verbatim: " / \(TapeNames.duration(ms: durationMs))")
                .font(DeckFont.monoBold.fixed(12))
                .foregroundStyle(lit.opacity(0.55))
            if flags > 0 {
                Text(verbatim: "  \(Glyph.flag)\(flags)")
                    .font(DeckFont.monoBold.fixed(12))
                    .foregroundStyle(palette.danger)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            LinearGradient(colors: [.black, palette.counterBg, .black], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 4)
        )
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(palette.key2, lineWidth: 2))
        .accessibilityElement(children: .combine)
    }
}
