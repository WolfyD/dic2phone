import SwiftUI

/// One line while recording: held or locked, noise activation, the tape so far, flags.
struct RecStatus: View {
    let state: RecorderState

    @Environment(\.palette) private var palette

    var body: some View {
        Text(verbatim: parts.joined(separator: "  ·  "))
            .font(DeckFont.monoBold.fixed(12))
            .foregroundStyle(state.vox && !state.rolling ? palette.dim : palette.led)
            .lineLimit(1)
    }

    private var parts: [String] {
        var parts = [state.latched ? String(localized: "LOCKED") : String(localized: "HOLDING")]
        if state.vox {
            parts.append(state.rolling ? String(localized: "VOX · ROLLING") : String(localized: "VOX · WAITING FOR SOUND"))
        }
        if state.vox || state.part > 1 {
            parts.append(String(localized: "ON TAPE \(TapeNames.duration(ms: state.tapeMs))"))
        }
        if state.part > 1 {
            parts.append(String(localized: "TAPE \(state.part)"))
        }
        if state.flags > 0 {
            parts.append("⚑ \(state.flags)")
        }
        return parts
    }
}
