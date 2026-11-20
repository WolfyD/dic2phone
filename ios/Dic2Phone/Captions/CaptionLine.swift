import SwiftUI

/// The caption being spoken, subtitle style. Always three lines tall, so the keys below stay put
/// as captions come and go: a finger holding FF mustn't find the key moved from under it.
struct CaptionLine: View {
    static let height: CGFloat = 3 * 19 + 10
    private static let subtitleColor = Color(hex: 0xFFF4C8)

    let text: String?

    var body: some View {
        ZStack {
            if let text {
                Text(verbatim: text)
                    .font(DeckFont.monoBold.fixed(15))
                    .foregroundStyle(Self.subtitleColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
    }
}
