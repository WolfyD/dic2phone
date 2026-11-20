import SwiftUI

/// A deck tape as a cassette case seen edge-on: smoky clear plastic with the J-card's spine
/// showing through, and a little ⏏ key on the end that puts it straight into the deck.
struct TapeCaseRow: View {
    private static let height: CGFloat = 58

    let tape: Tape
    let state: TapeRowState
    let loadMode: Bool
    let actions: TapeRowActions

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            spine
            if !loadMode {
                LoadKey(enabled: !state.inDeck, action: actions.load)
            }
        }
        .padding(.leading, 5)
        .padding(.vertical, 5)
        .padding(.trailing, loadMode ? 5 : 0)
        .frame(height: Self.height)
        .background(LinearGradient(
            colors: [Color(hex: 0x45454B), Color(hex: 0x232327), Color(hex: 0x111113)],
            startPoint: .top, endPoint: .bottom
        ))
        .overlay(alignment: .top) { gloss }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(state.selected ? palette.danger : .black, lineWidth: state.selected ? 2.5 : 1)
        )
    }

    private var spine: some View {
        let (date, time) = TapeNames.dateAndTime(tape.id)
        return HStack(spacing: 0) {
            LabelStripes()
                .frame(width: 16)
            Text(verbatim: stateGlyph)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(state.selected ? palette.danger : palette.ink)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 0) {
                TapeTitleText(title: tape.title, fallback: date, color: palette.ink, size: 15)
                HStack(spacing: 8) {
                    Text(verbatim: tape.title.isEmpty ? time : "\(date) \(time)")
                        .font(DeckFont.mono.fixed(12))
                        .foregroundStyle(palette.ink.opacity(0.75))
                        .lineLimit(1)
                    if state.playing {
                        TapeProgress(progress: state.progress, track: palette.ink.opacity(0.15))
                            .frame(height: 4)
                            .padding(.trailing, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            badges
            Text(verbatim: TapeNames.duration(ms: tape.durationMs))
                .font(DeckFont.monoBold.fixed(14))
                .foregroundStyle(palette.ink)
                .padding(.trailing, 10)
        }
        .frame(maxHeight: .infinity)
        .background(palette.label, in: RoundedRectangle(cornerRadius: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: actions.tap)
        .onLongPressGesture(perform: actions.select)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(state.selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: Text(state.selected ? "Deselect" : "Select"), actions.select)
    }

    @ViewBuilder private var badges: some View {
        if state.inDeck {
            TapeBadge(text: String(localized: "IN DECK"), foreground: palette.label, background: palette.ink)
                .padding(.trailing, 6)
        }
        if tape.isNew {
            TapeBadge(text: String(localized: "NEW"), foreground: .white, background: palette.danger)
                .padding(.trailing, 6)
        }
        if tape.hasCaptions || state.transcribing {
            TranscriptBadge(transcribing: state.transcribing, ink: palette.ink)
                .padding(.trailing, 8)
        }
    }

    private var stateGlyph: String {
        if state.selected { return Glyph.check }
        if loadMode { return Glyph.eject }
        return state.playing ? Glyph.stop : Glyph.play
    }

    /// The clear case's shine: a bright top edge fading down over the label.
    private var gloss: some View {
        VStack(spacing: 0) {
            Color.white.opacity(0.28)
                .frame(height: 1)
            LinearGradient(colors: [.white.opacity(0.13), .clear], startPoint: .top, endPoint: .bottom)
        }
        .frame(height: Self.height / 2)
        .allowsHitTesting(false)
    }
}
