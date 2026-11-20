import SwiftUI

/// The deck as a player for the tape that's in: the position strip with its flags, the play
/// time, the captions, the compartment of less-used keys, and the transport keys unless they sit
/// elsewhere.
struct DeckPlayer: View {
    private static let compartmentKeyHeight: CGFloat = 38

    let tape: Tape
    /// Nil when the keys are in the deck's own key row instead, as in landscape.
    let transport: [BankKey]?

    @Environment(Player.self) private var player
    @Environment(TapeLibrary.self) private var library
    @Environment(CaptionQueue.self) private var captions

    @State private var transcribing: [Tape]?

    var body: some View {
        VStack(spacing: 4) {
            ScrubStrip(
                durationMs: tape.durationMs,
                positionMs: player.deckPositionMs,
                flags: tape.flags,
                onSeek: { player.seek(toMs: $0) },
                onFlag: { player.jump(toFlag: $0) }
            )
            TimeWindow(
                positionMs: player.deckPositionMs,
                durationMs: tape.durationMs,
                flags: tape.flags.count,
                playing: player.deckPlaying
            )
            DeckCaptions(tape: tape)
            compartment
            if let transport {
                KeyBank(keys: transport, keyHeight: 52)
            }
        }
        .transcribeRequest($transcribing)
    }

    private var compartment: some View {
        let neighbours = FlagNeighbours(flags: tape.flags, positionMs: player.deckPositionMs)
        return DeckCompartment {
            flagKey(Glyph.previousFlag, to: neighbours.previous)
                .accessibilityLabel(Text("Previous flag"))
            flagKey(Glyph.nextFlag, to: neighbours.next)
                .accessibilityLabel(Text("Next flag"))
            if canTranscribe {
                DeckKey(label: String(localized: "TRANSCRIBE"), height: Self.compartmentKeyHeight) {
                    transcribing = [tape]
                }
                .layoutWeight(1.8)
            }
        }
    }

    private func flagKey(_ label: String, to flag: Int64?) -> some View {
        DeckKey(label: label, height: Self.compartmentKeyHeight) {
            if let flag { player.seek(toMs: flag) }
        }
        .disabled(flag == nil)
    }

    private var canTranscribe: Bool {
        !tape.hasCaptions && library.transcripts[tape.id] == nil && !captions.waitingTapes.contains(tape.id)
    }
}
