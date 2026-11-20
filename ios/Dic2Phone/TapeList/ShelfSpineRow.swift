import SwiftUI

/// A shelved tape: a cassette case's spine standing in the rack, with a lamp that lights while
/// it plays.
struct ShelfSpineRow: View {
    let tape: Tape
    let state: TapeRowState
    let actions: TapeRowActions

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                spine
                LoadKey(enabled: !state.inDeck, action: actions.load)
            }
            .padding(.leading, 6)
            .padding(.vertical, 5)
            .frame(height: 48)
            .background(LinearGradient(colors: [Color(hex: 0x3B3B40), Color(hex: 0x151517)], startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(state.selected ? palette.danger : .clear, lineWidth: 2)
            )
            if state.playing {
                TapeProgress(progress: state.progress, track: .black)
                    .frame(height: 3)
            }
        }
    }

    private var spine: some View {
        HStack(spacing: 0) {
            LabelStripes()
                .frame(width: 22)
            label
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity)
                .background(palette.label)
            Circle()
                .fill(state.playing ? palette.led : Color(hex: 0x555555))
                .frame(width: 10, height: 10)
                .padding(.leading, 6)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: actions.tap)
        .onLongPressGesture(perform: actions.select)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(state.selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: Text(state.selected ? "Deselect" : "Select"), actions.select)
    }

    private var label: some View {
        let (date, time) = TapeNames.dateAndTime(tape.id)
        return HStack(spacing: 0) {
            if state.selected || state.playing {
                Text(verbatim: "\(state.selected ? Glyph.check : Glyph.stop) ")
                    .font(DeckFont.monoBold.fixed(13))
                    .foregroundStyle(palette.danger)
            }
            Group {
                if tape.title.isEmpty {
                    TapeTitleText(title: "", fallback: "\(date)  \(time)", color: palette.ink, size: 13)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        TapeTitleText(title: tape.title, fallback: "", color: palette.ink, size: 12)
                        Text(verbatim: "\(date)  \(time)")
                            .font(DeckFont.mono.fixed(10))
                            .foregroundStyle(palette.ink.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if tape.hasCaptions || state.transcribing {
                TranscriptBadge(transcribing: state.transcribing, ink: palette.ink)
                    .padding(.trailing, 8)
            }
            Text(verbatim: TapeNames.duration(ms: tape.durationMs))
                .font(DeckFont.mono.fixed(12))
                .foregroundStyle(palette.ink)
        }
    }
}
