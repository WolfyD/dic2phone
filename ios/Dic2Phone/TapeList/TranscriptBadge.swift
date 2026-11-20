import SwiftUI

/// A "TXT" box on a tape with a transcript, "TXT…" while one is being made.
struct TranscriptBadge: View {
    let transcribing: Bool
    let ink: Color

    @Environment(\.palette) private var palette

    var body: some View {
        let color = transcribing ? palette.accent : ink
        Text(verbatim: String(localized: "TXT") + (transcribing ? "…" : ""))
            .font(DeckFont.monoBold.fixed(10))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(color, lineWidth: 1.5))
            .accessibilityLabel(transcribing ? Text("Being transcribed") : Text("Transcribed"))
    }
}
