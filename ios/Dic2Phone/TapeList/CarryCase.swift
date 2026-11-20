import SwiftUI

/// The black plastic carry case the deck's tapes stand in, spines out.
struct CarryCase<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 3) {
                content
            }
            .padding(6)
        }
        .background(LinearGradient(colors: [Color(hex: 0x1A1A1C), Color(hex: 0x0A0A0B)], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: 0x2C2C30), lineWidth: 2))
        .shadow(radius: 4)
    }
}
