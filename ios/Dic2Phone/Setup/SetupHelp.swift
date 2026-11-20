import SwiftUI

/// What a setting does, in small print; a warning when it can't do it right now.
struct SetupHelp: View {
    let text: String
    var warning = false

    @Environment(\.palette) private var palette

    var body: some View {
        Text(verbatim: text)
            .font(DeckFont.mono.fixed(12))
            .foregroundStyle(warning ? palette.accent : palette.dim)
            .fixedSize(horizontal: false, vertical: true)
    }
}
