import SwiftUI

/// The deck as a player for the tape that's in: the position strip with its flags, the play
/// time and the note on the flag just passed, the captions, the compartment of less-used keys
/// and the tape's info, and the transport keys unless they sit elsewhere.
struct DeckPlayer: View {
    private static let compartmentKeyHeight: CGFloat = 38

    let tape: Tape
    /// Nil when the keys are in the deck's own key row instead, as in landscape.
    let transport: [BankKey]?

    @Environment(Player.self) private var player
    @Environment(TapeLibrary.self) private var library
    @Environment(CaptionQueue.self) private var captions

    @State private var transcribing: [Tape]?
    @State private var showingInfo = false
    @State private var noting: Int64?

    var body: some View {
        let neighbours = FlagNeighbours(flags: tape.flags, positionMs: player.deckPositionMs)
        return VStack(spacing: 4) {
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
            FlagNoteLine(flag: neighbours.passed, note: neighbours.passed.flatMap { tape.flagNotes[$0] } ?? "") {
                noting = neighbours.passed
            }
            DeckCaptions(tape: tape)
            compartment(neighbours)
            if let transport {
                KeyBank(keys: transport, keyHeight: 52)
            }
        }
        .transcribeRequest($transcribing)
        .sheet(isPresented: $showingInfo) {
            TapeInfoSheet(tape: tape) { showingInfo = false }
        }
        .labelWritingAlert(
            isPresented: Binding { noting != nil } set: { if !$0 { noting = nil } },
            title: String(localized: "NOTE ON THIS FLAG"),
            original: noting.flatMap { tape.flagNotes[$0] } ?? "",
            placeholder: "",
            limit: TapeMeta.flagNoteLimit,
            hint: noting.map { Glyph.flag + " " + TapeNames.duration(ms: $0) } ?? "",
            learnsWords: tape.rack != .vault,
            onWrite: { [noting, tape] note in
                // Captured now: closing the alert clears `noting` before or after WRITE runs.
                guard let noting else { return }
                Task { await library.setFlagNote(note, at: noting, of: tape) }
            }
        )
    }

    private func compartment(_ neighbours: FlagNeighbours) -> some View {
        DeckCompartment {
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
            DeckKey(label: String(localized: "INFO"), height: Self.compartmentKeyHeight) { showingInfo = true }
                .layoutWeight(1.1)
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
