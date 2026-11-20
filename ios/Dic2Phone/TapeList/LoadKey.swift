import SwiftUI

/// The little ⏏ key on the end of a tape case: straight into the deck.
struct LoadKey: View {
    let enabled: Bool
    let action: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Text(verbatim: Glyph.eject)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(palette.keyText)
        }
        .buttonStyle(PianoKeyStyle(height: 40, face1: palette.key1, face2: palette.key2, latched: false))
        .frame(width: 34)
        .opacity(enabled ? 1 : 0.35)
        .frame(width: 46)
        .disabled(!enabled)
        .accessibilityLabel(Text("Put in deck"))
    }
}
