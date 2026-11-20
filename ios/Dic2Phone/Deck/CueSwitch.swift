import SwiftUI

/// TAPE WIND's CUE switch, beside the position strip: a lamp with CUE printed under it, and a
/// little slide switch. Lit, the tape is heard as it winds. A tap anywhere on it flicks it.
struct CueSwitch: View {
    static let width: CGFloat = 72
    private static let height: CGFloat = 40
    private static let lampDiameter: CGFloat = 9
    private static let slot = CGSize(width: 30, height: 16)
    private static let nubInset: CGFloat = 2

    @Environment(Settings.self) private var settings
    @Environment(\.palette) private var palette
    @Environment(\.detentClick) private var detentClick

    var body: some View {
        Button {
            detentClick()
            withAnimation(.spring(response: 0.16, dampingFraction: 0.7)) { settings.windCue.toggle() }
        } label: {
            HStack(spacing: 8) {
                VStack(spacing: 3) {
                    Led(on: settings.windCue, diameter: Self.lampDiameter)
                    Text(verbatim: "CUE")
                        .font(DeckFont.monoBold.fixed(9))
                        .tracking(1)
                        .foregroundStyle(palette.dim)
                }
                slide
            }
            .frame(width: Self.width, height: Self.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Cue"))
        .accessibilityValue(settings.windCue ? Text("On") : Text("Off"))
        .accessibilityHint(Text("Hear the tape as it winds"))
    }

    private var slide: some View {
        let nub = CGSize(width: Self.slot.width / 2, height: Self.slot.height - 2 * Self.nubInset)
        let travel = Self.slot.width - nub.width - 2 * Self.nubInset
        return RoundedRectangle(cornerRadius: 3)
            .fill(.black)
            .frame(width: Self.slot.width, height: Self.slot.height)
            .overlay(alignment: .leading) {
                SlideNub(face1: palette.key1, face2: palette.key2)
                    .frame(width: nub.width, height: nub.height)
                    .offset(x: Self.nubInset + (settings.windCue ? travel : 0))
            }
    }
}
