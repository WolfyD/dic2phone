import SwiftUI

/// The deck's subtitle window: what's being said right now, or how far along the transcript is.
/// It takes no room on a tape that has no transcript coming.
struct DeckCaptions: View {
    let tape: Tape

    @Environment(TapeLibrary.self) private var library
    @Environment(CaptionQueue.self) private var captions
    @Environment(Player.self) private var player
    @Environment(\.palette) private var palette

    var body: some View {
        window
            .task(id: tape) { await library.loadTranscript(of: tape) }
    }

    @ViewBuilder
    private var window: some View {
        if let transcript = library.transcripts[tape.id] {
            if transcript.cues.isEmpty {
                note(String(localized: "NO SPEECH FOUND ON THIS TAPE"), color: palette.dim)
            } else {
                CaptionLine(text: transcript.cue(atMs: player.deckPositionMs)?.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: CaptionLine.height)
            }
        } else if captions.waitingTapes.contains(tape.id) {
            note(progress, color: palette.led)
        } else if tape.hasCaptions {
            // Still reading it: the window's already there, so nothing shifts when it arrives.
            note("", color: palette.dim)
        }
    }

    private var progress: String {
        guard let status = captions.status, status.tape == tape.id else {
            return String(localized: "WAITING TO TRANSCRIBE…")
        }
        return String(localized: "TRANSCRIBING · \(status.step.line) \(status.percent)%")
    }

    private func note(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(DeckFont.mono.fixed(12))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: .infinity)
            .frame(height: CaptionLine.height)
    }
}
