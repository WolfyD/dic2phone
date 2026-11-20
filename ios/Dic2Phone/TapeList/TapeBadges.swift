import SwiftUI

/// A tape's tags: IN DECK, NEW, when AUTO-TIDY takes it, and its transcript. Compact, on a
/// stacked disc's narrow edge, IN DECK shrinks to ◉ and the tidy date waits for the disc to be
/// pulled out.
struct TapeBadges: View {
    let tape: Tape
    let state: TapeRowState
    var compact = false

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            if state.inDeck {
                TapeBadge(text: compact ? Glyph.inDeck : String(localized: "IN DECK"), foreground: palette.label, background: palette.ink)
                    .accessibilityLabel(Text("In the deck"))
            }
            if tape.isNew {
                TapeBadge(text: String(localized: "NEW"), foreground: .white, background: palette.danger)
            }
            if !compact, let tidiedAt = state.tidiedAt {
                let when = AutoTidy.whenText(of: tidiedAt, now: .now)
                TapeBadge(text: "✂ \(when)", foreground: .white, background: palette.accent)
                    .accessibilityLabel(Text("Auto-tidy deletes it \(when)"))
            }
            if tape.hasCaptions || state.transcribing {
                TranscriptBadge(transcribing: state.transcribing, ink: palette.ink)
            }
        }
    }
}
