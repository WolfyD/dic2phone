import SwiftUI

/// A small coloured tag on a tape: NEW, IN DECK.
struct TapeBadge: View {
    let text: String
    let foreground: Color
    let background: Color

    var body: some View {
        Text(verbatim: text)
            .font(DeckFont.monoBold.fixed(11))
            .foregroundStyle(foreground)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(background, in: RoundedRectangle(cornerRadius: 3))
    }
}
