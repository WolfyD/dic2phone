import SwiftUI

/// The tape playing from a search hit: what's being said, and a key to stop it.
struct SearchPlaying: View {
    let tape: Tape
    let transcript: Transcript

    @Environment(Player.self) private var player

    var body: some View {
        VStack(spacing: 4) {
            CaptionLine(text: transcript.cue(atMs: player.positionMs)?.text)
            DeckKey(label: String(localized: "\(Glyph.stop) STOP  \(TapeNames.duration(ms: player.positionMs))"), height: 44, action: player.stop)
        }
        .padding(6)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }
}
