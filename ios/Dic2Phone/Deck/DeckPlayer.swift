import SwiftUI

/// The deck as a player for the tape that's in: the position strip with its flags, the play
/// time, and the transport keys unless they sit elsewhere.
struct DeckPlayer: View {
    let tape: Tape
    /// Nil when the keys are in the deck's own key row instead, as in landscape.
    let transport: [BankKey]?

    @Environment(Player.self) private var player

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
            if let transport {
                KeyBank(keys: transport, keyHeight: 52)
            }
        }
    }
}
