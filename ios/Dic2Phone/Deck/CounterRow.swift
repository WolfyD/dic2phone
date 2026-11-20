import SwiftUI

/// The new-tape counter on the left; the REC lamp, time recorded and tapes on the deck on the
/// right.
struct CounterRow: View {
    let newCount: Int
    let recording: Bool
    let elapsedMs: Int64
    let onDeck: Int
    let onReset: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        HStack {
            VStack(spacing: 0) {
                TapeCounter(value: newCount, onReset: onReset)
                Text("NEW TAPES")
                    .font(DeckFont.mono.fixed(11))
                    .foregroundStyle(palette.dim)
                    .accessibilityHidden(true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: 4) {
                    Text("REC")
                        .font(DeckFont.mono.fixed(12))
                        .foregroundStyle(palette.dim)
                    Led(on: recording)
                }
                Text(verbatim: TapeNames.duration(ms: elapsedMs))
                    .font(DeckFont.monoBold.fixed(30))
                    .foregroundStyle(recording ? palette.led : palette.dim)
                Text("\(onDeck) ON DECK")
                    .font(DeckFont.mono.fixed(11))
                    .foregroundStyle(palette.dim)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
