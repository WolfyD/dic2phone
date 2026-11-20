import SwiftUI

/// A mechanical three-digit counter of new tapes, its digits rolling over, with a reset button
/// in the same window like on a real deck.
struct TapeCounter: View {
    let value: Int
    let onReset: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.keyClick) private var keyClick

    private var digits: [Character] {
        let shown = String(min(max(value, 0), 999))
        return Array(String(repeating: "0", count: 3 - shown.count) + shown)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(digits.indices, id: \.self) { index in
                    digit(digits[index])
                }
            }
            .animation(.snappy, value: value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(value) new tapes"))
            Button {
                keyClick()
                onReset()
            } label: {
                EmptyView()
            }
            .buttonStyle(CounterResetStyle(palette: palette))
            .accessibilityLabel(Text("Reset new-tape counter"))
            .padding(.leading, 8)
            .padding(.trailing, 4)
        }
        .padding(4)
        .background(.black, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(palette.key2, lineWidth: 2))
    }

    private func digit(_ digit: Character) -> some View {
        Text(verbatim: String(digit))
            .font(DeckFont.monoBold.fixed(28))
            .foregroundStyle(palette.counterDigit)
            .contentTransition(.numericText(value: Double(value)))
            .frame(width: 30, height: 42)
            .background(LinearGradient(
                colors: [palette.counterBg, palette.counterBg.lightened(by: 0.18), palette.counterBg],
                startPoint: .top, endPoint: .bottom
            ))
            .clipped()
            .padding(.horizontal, 2)
    }
}
