import SwiftUI

/// The note on the flag just passed, under the time window; a tap writes it. The line is blank
/// off a flag but always there, so winding past flags moves nothing.
struct FlagNoteLine: View {
    private static let height: CGFloat = 16

    let flag: Int64?
    let note: String
    let write: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: write) {
            Text(verbatim: text)
                .font(DeckFont.mono.fixed(11))
                .foregroundStyle(note.isEmpty ? palette.dim : palette.accent)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(flag == nil)
        .accessibilityHidden(flag == nil)
        .accessibilityHint(Text("Writes a note on this flag"))
    }

    private var text: String {
        guard flag != nil else { return "" }
        return Glyph.flag + " " + (note.isEmpty ? String(localized: "tap to add a note") : note)
    }
}
