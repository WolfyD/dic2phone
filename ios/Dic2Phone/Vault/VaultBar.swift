import SwiftUI

/// Under the shelf: the steel door to the vault.
struct VaultBar: View {
    let isOpen: Bool
    let count: Int
    let action: () -> Void

    @Environment(\.keyClick) private var keyClick

    var body: some View {
        Button {
            keyClick()
            action()
        } label: {
            HStack(spacing: 10) {
                Text(verbatim: isOpen ? Glyph.unlocked : Glyph.locked)
                    .font(.system(size: 18))
                Text("THE VAULT")
                    .font(DeckFont.monoBold.fixed(15))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: status)
                    .font(DeckFont.mono.fixed(12))
            }
            .foregroundStyle(Steel.ink)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(Steel.plate, in: RoundedRectangle(cornerRadius: 6))
            .shadow(radius: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("THE VAULT"))
        .accessibilityValue(Text(verbatim: status))
    }

    private var status: String {
        isOpen
            ? String(localized: "\(count) tapes · open \(Glyph.play)")
            : String(localized: "locked \(Glyph.play)")
    }
}
