import SwiftUI

/// The shelf: a wooden rack holding tapes as cassette-case spines.
struct ShelfRack<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            side
            ScrollView {
                LazyVStack(spacing: 4) {
                    content
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .background(Color(hex: 0x24170D))
            side
        }
        .background(Color(hex: 0x3E2716))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var side: some View {
        LinearGradient(
            colors: [Color(hex: 0x5A3A22), Color(hex: 0x7A5232), Color(hex: 0x5A3A22)],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(width: 12)
    }
}
