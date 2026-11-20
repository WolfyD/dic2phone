import SwiftUI

/// The tape playing from a list, in a cassette with its reels turning, and a key to stop it.
struct NowPlaying: View {
    let tape: Tape

    @Environment(Player.self) private var player
    @Environment(Settings.self) private var settings

    var body: some View {
        HStack(spacing: 10) {
            CassetteView(
                label: .playing(tape, positionMs: player.positionMs),
                spinning: true,
                progress: progress,
                typed: settings.labelTyped
            )
            .frame(height: 96)
            DeckKey(label: String(localized: "\(Glyph.stop) STOP"), height: 64, action: player.stop)
        }
        .padding(6)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private var progress: CGFloat {
        guard tape.durationMs > 0 else { return 0 }
        return min(max(CGFloat(player.positionMs) / CGFloat(tape.durationMs), 0), 1)
    }
}
