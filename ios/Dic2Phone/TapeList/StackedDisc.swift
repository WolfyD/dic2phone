import SwiftUI

/// A tape as a MiniDisc in a stack. Only its top edge shows, with the label's strip; pulled out,
/// the whole disc shows, the label grows to the full details, and keys appear beside the shutter.
struct StackedDisc: View {
    /// How much of a disc the stack shows.
    static let strip: CGFloat = 50
    private static let edgeRowHeight: CGFloat = 38
    private static let shells = [
        Color(hex: 0x26262B), Color(hex: 0xC62A3C), Color(hex: 0xE2702A), Color(hex: 0x3E9E4C),
        Color(hex: 0x27AEC2), Color(hex: 0x7A3FB6), Color(hex: 0x5A6C8A),
    ]

    let tape: Tape
    let state: TapeRowState
    let lifted: Bool
    let loadMode: Bool
    /// The whole disc's height.
    let height: CGFloat
    let tap: () -> Void
    let actions: TapeRowActions

    @Environment(\.palette) private var palette

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                art.draw(in: context, size: size)
            }
            label
                .padding(.leading, StackedDiscArt.outline.cut + 6)
                .padding(.trailing, 8)
                .padding(.top, 6)
        }
        .frame(height: height)
        .contentShape(StackedDiscArt.outline)
        .onTapGesture(perform: tap)
        .onLongPressGesture(perform: actions.select)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(state.selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: Text(state.selected ? "Deselect" : "Select"), actions.select)
        .overlay(alignment: .bottomTrailing) {
            if lifted {
                keys
            }
        }
    }

    private var art: StackedDiscArt {
        StackedDiscArt(
            shell: shell,
            edge: state.selected ? palette.danger : .black.opacity(0.55),
            edgeWidth: state.selected ? 3 : 1
        )
    }

    /// Each tape keeps its colour from one visit to the next.
    private var shell: Color {
        var random = SeededRandom(text: tape.id.fileName)
        return Self.shells[Int(random.next() % UInt64(Self.shells.count))]
    }

    private var label: some View {
        let (date, time) = TapeNames.dateAndTime(tape.id)
        return VStack(spacing: 0) {
            edgeRow(date: date, time: time)
            if lifted {
                details(date: date, time: time)
            }
        }
        .frame(height: lifted ? height * 0.62 - 16 : Self.edgeRowHeight, alignment: .top)
        .background(palette.label)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func edgeRow(date: String, time: String) -> some View {
        HStack(spacing: 0) {
            LabelStripes()
                .frame(width: 10)
                .padding(.trailing, 6)
            if state.selected || state.playing {
                Text(verbatim: "\(state.selected ? Glyph.check : Glyph.stop) ")
                    .font(DeckFont.monoBold.fixed(13))
                    .foregroundStyle(palette.danger)
            }
            titles(date: date, time: time)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !lifted {
                TapeBadges(tape: tape, state: state, compact: true)
                    .padding(.trailing, 4)
            }
            Text(verbatim: TapeNames.duration(ms: tape.durationMs))
                .font(DeckFont.monoBold.fixed(13))
                .foregroundStyle(palette.ink)
                .padding(.trailing, 8)
        }
        .frame(height: Self.edgeRowHeight)
    }

    /// Untitled tapes go by their date. Pulled out, the date moves down to the details.
    @ViewBuilder
    private func titles(date: String, time: String) -> some View {
        if tape.title.isEmpty {
            TapeTitleText(title: "", fallback: "\(date)  \(time)", color: palette.ink, size: 13)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                TapeTitleText(title: tape.title, fallback: "", color: palette.ink, size: 12)
                if !lifted {
                    Text(verbatim: "\(date)  \(time)")
                        .font(DeckFont.mono.fixed(10))
                        .foregroundStyle(palette.ink.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
    }

    private func details(date: String, time: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            palette.ink.opacity(0.3)
                .frame(height: 1)
            if !tape.title.isEmpty {
                Text(verbatim: "\(date)  \(time)")
                    .font(DeckFont.monoBold.fixed(13))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
            }
            TapeBadges(tape: tape, state: state)
            Spacer(minLength: 0)
            if state.playing {
                TapeProgress(progress: state.progress, track: palette.ink.opacity(0.15))
                    .frame(height: 4)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var keys: some View {
        HStack(alignment: .bottom, spacing: 6) {
            DeckKey(label: playGlyph, height: 44, action: actions.tap)
                .frame(width: 56)
                .accessibilityLabel(playLabel)
            if !loadMode {
                LoadKey(enabled: !state.inDeck, action: actions.load)
            }
        }
        .padding(.trailing, 10)
        .padding(.bottom, 12)
    }

    private var playGlyph: String {
        if loadMode { return Glyph.eject }
        return state.playing ? Glyph.stop : Glyph.play
    }

    private var playLabel: Text {
        if loadMode { return Text("Put in deck") }
        return state.playing ? Text("Stop") : Text("Play")
    }
}
