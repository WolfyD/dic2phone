import SwiftUI

/// A piano key with its label printed on the key itself, for the lists' and setup's keys.
struct DeckKey: View {
    let label: String
    var height: CGFloat = 52
    var labelColor: Color?
    let action: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.keyClick) private var keyClick
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            keyClick()
            action()
        } label: {
            Text(verbatim: label)
                .font(DeckFont.monoBold.fixed(13))
                .tracking(1)
                .foregroundStyle(labelColor ?? palette.keyText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
        }
        .buttonStyle(PianoKeyStyle(height: height, face1: palette.key1, face2: palette.key2, latched: false))
        .opacity(isEnabled ? 1 : 0.4)
    }
}
