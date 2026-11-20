import SwiftUI

/// A tape's title in the user's pen (or typed, if they chose that), or the fallback printed.
struct TapeTitleText: View {
    let title: String
    let fallback: String
    let color: Color
    let size: CGFloat

    @Environment(Settings.self) private var settings

    var body: some View {
        let handwritten = !title.isEmpty && !settings.labelTyped
        Text(verbatim: title.isEmpty ? fallback : title)
            // The handwriting face is small for its point size; 1.45 matches it to the printed text.
            .font(handwritten ? DeckFont.hand.fixed(size * 1.45) : DeckFont.monoBold.fixed(size))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
