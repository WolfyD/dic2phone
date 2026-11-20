import SwiftUI

/// A small preview of a theme: its backdrop with a cassette in its colours. Tapping it loads it.
struct ThemeCard: View {
    let theme: Palette
    let loaded: Bool
    let onLoad: () -> Void

    @Environment(\.keyClick) private var keyClick

    var body: some View {
        Button {
            keyClick()
            onLoad()
        } label: {
            preview
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: theme.name))
        .accessibilityAddTraits(loaded ? .isSelected : [])
    }

    private var preview: some View {
        VStack(spacing: 6) {
            CassetteView(label: CassetteLabel(title: "", subtitle: "", handwritten: false), spinning: false, progress: 0.3, typed: false)
            LabelStripes()
                .frame(width: 48, height: 3)
            Text(verbatim: theme.name)
                .font(DeckFont.monoBold.fixed(10))
                .foregroundStyle(theme.text)
                .lineLimit(1)
            Text(verbatim: loaded ? "\(Glyph.chosen) \(String(localized: "LOADED"))" : " ")
                .font(DeckFont.mono.fixed(9))
                .foregroundStyle(theme.accent)
        }
        .padding(8)
        .frame(width: 132)
        .background { DeckBackground(palette: theme) }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(loaded ? theme.accent : .black.opacity(0.4), lineWidth: loaded ? 3 : 1)
        }
        .environment(\.palette, theme)
    }
}
