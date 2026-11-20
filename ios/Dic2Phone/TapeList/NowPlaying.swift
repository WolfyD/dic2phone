import SwiftUI

/// The tape playing from a list, in a cassette with its reels turning, and a key to stop it.
/// A transcribed tape also shows what's being said, and a key to read the whole transcript.
struct NowPlaying: View {
    let tape: Tape
    let read: () -> Void

    @Environment(Player.self) private var player
    @Environment(Settings.self) private var settings
    @Environment(TapeLibrary.self) private var library

    var body: some View {
        let transcript = library.transcripts[tape.id]
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                CassetteView(
                    label: .playing(tape, positionMs: player.positionMs),
                    spinning: true,
                    progress: progress,
                    typed: settings.labelTyped
                )
                .frame(height: 96)
                keys(readable: transcript != nil)
            }
            if let transcript {
                CaptionLine(text: transcript.cue(atMs: player.positionMs)?.text)
            }
        }
        .padding(6)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .task(id: tape) { await library.loadTranscript(of: tape) }
    }

    private func keys(readable: Bool) -> some View {
        VStack(spacing: 6) {
            DeckKey(label: String(localized: "\(Glyph.stop) STOP"), height: readable ? 45 : 64, action: player.stop)
            if readable {
                DeckKey(label: String(localized: "TEXT"), height: 45, action: read)
            }
        }
    }

    private var progress: CGFloat {
        guard tape.durationMs > 0 else { return 0 }
        return min(max(CGFloat(player.positionMs) / CGFloat(tape.durationMs), 0), 1)
    }
}
