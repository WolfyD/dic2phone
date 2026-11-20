import SwiftUI

/// A labelled text box in TAPE INFO, cut off at `limit` letters.
struct TapeInfoField: View {
    let label: String
    @Binding var text: String
    let limit: Int
    var placeholder = ""
    var multiline = false
    /// Off for vault tapes, so what's written about them stays out of the keyboard's learned words.
    var learnsWords = true

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: label)
                .font(DeckFont.monoBold.fixed(11))
                .foregroundStyle(palette.dim)
            TextField(
                "",
                text: $text,
                prompt: Text(verbatim: placeholder).foregroundStyle(palette.dim),
                axis: multiline ? .vertical : .horizontal
            )
            .lineLimit(multiline ? 2...6 : 1...1)
            .font(DeckFont.mono.fixed(14))
            .foregroundStyle(palette.text)
            .tint(palette.accent)
            .textInputAutocapitalization(.sentences)
            .autocorrectionDisabled(!learnsWords)
            .padding(10)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.dim, lineWidth: 1))
            .onChange(of: text) { _, typed in
                if typed.count > limit { text = String(typed.prefix(limit)) }
            }
        }
    }
}
