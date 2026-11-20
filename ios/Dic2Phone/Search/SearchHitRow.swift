import SwiftUI

/// One place the searched words were said: which tape and when, and the caption with the words
/// marked. It lights up while that caption plays; tapping it plays from there.
struct SearchHitRow: View {
    let hit: CaptionHit
    let play: () -> Void

    @Environment(Player.self) private var player
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: place)
                    .font(DeckFont.mono.fixed(11))
                    .foregroundStyle(palette.ink.opacity(0.65))
                Text(marked)
                    .font(DeckFont.mono.fixed(14))
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isPlaying ? palette.accent.opacity(0.35) : palette.label, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Plays the tape from here"))
    }

    private var place: String {
        let lock = hit.tape.rack == .vault ? Glyph.locked + " " : ""
        return lock + TapeNames.label(hit.tape) + "  \(Glyph.play) " + TapeNames.duration(ms: hit.cue.startMs)
    }

    private var isPlaying: Bool {
        let position = player.positionMs
        return player.playingID == hit.tape.id
            && position >= hit.cue.startMs && position <= hit.cue.endMs + Transcript.lingerMs
    }

    private var marked: AttributedString {
        var text = AttributedString(hit.cue.text)
        let characters = text.characters
        guard hit.characters.upperBound <= characters.count else { return text }
        let start = characters.index(characters.startIndex, offsetBy: hit.characters.lowerBound)
        let end = characters.index(start, offsetBy: hit.characters.count)
        text[start..<end].font = DeckFont.monoBold.fixed(14)
        text[start..<end].backgroundColor = palette.accent.opacity(0.55)
        return text
    }
}
