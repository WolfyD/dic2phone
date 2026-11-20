import SwiftUI

/// One caption in a transcript: when it's said, and what. Tapping it plays the tape from there.
struct TranscriptLine: View {
    let cue: Cue
    let isCurrent: Bool
    let play: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: play) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(verbatim: TapeNames.duration(ms: cue.startMs))
                    .font(DeckFont.mono.fixed(12))
                    .foregroundStyle(palette.ink.opacity(0.6))
                    .frame(width: 58, alignment: .leading)
                Text(verbatim: cue.text)
                    .font(isCurrent ? DeckFont.monoBold.fixed(14) : DeckFont.mono.fixed(14))
                    .foregroundStyle(palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isCurrent ? palette.accent.opacity(0.35) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Plays the tape from here"))
    }
}
