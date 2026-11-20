import SwiftUI

/// A rack holding tapes as cassette-case spines: the wooden shelf, or the vault's steel one.
struct ShelfRack<Content: View>: View {
    let material: RackMaterial
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
            .background(material.back)
            side
        }
        .background(material.frame)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var side: some View {
        LinearGradient(colors: material.side, startPoint: .leading, endPoint: .trailing)
            .frame(width: 12)
    }
}
