import SwiftUI

/// The deck's subtitle window: what's being said right now, how far along the transcript is,
/// or a key to make one.
struct DeckCaptions: View {
    let tape: Tape

    @Environment(TapeLibrary.self) private var library
    @Environment(CaptionQueue.self) private var captions
    @Environment(Player.self) private var player
    @Environment(\.palette) private var palette

    @State private var request: [Tape]?

    var body: some View {
        window
            .frame(maxWidth: .infinity)
            .frame(height: CaptionLine.height)
            .task(id: tape) { await library.loadTranscript(of: tape) }
            .transcribeRequest($request)
    }

    @ViewBuilder
    private var window: some View {
        if let transcript = library.transcripts[tape.id] {
            if transcript.cues.isEmpty {
                note(String(localized: "NO SPEECH FOUND ON THIS TAPE"), color: palette.dim)
            } else {
                CaptionLine(text: transcript.cue(atMs: player.deckPositionMs)?.text)
            }
        } else if captions.waitingTapes.contains(tape.id) {
            note(progress, color: palette.led)
        } else if !tape.hasCaptions {
            DeckKey(label: String(localized: "TRANSCRIBE"), height: 40) { request = [tape] }
                .frame(width: 180)
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
    }
}
