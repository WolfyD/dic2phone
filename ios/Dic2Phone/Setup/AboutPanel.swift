import SwiftUI

/// What the app is, who made it, its license, what it does with the user's data, and how it was
/// made.
struct AboutPanel: View {
    @Environment(\.keyClick) private var keyClick

    @State private var showingHowMade = false

    var body: some View {
        SetupPanel(title: String(localized: "ABOUT")) {
            SetupHelp(text: String(localized: "Dic2Phone turns your iPhone into a pocket dictaphone that looks, sounds and feels like an old cassette recorder. Hold REC to catch a thought, a meeting or a tune, then play it back with flags. Your recordings stay on your iPhone unless you share them."))
            SetupHeading(text: "Dic2Phone \(version)\n© 2026 WolfyD · wolfyden@gmail.com")
                .textSelection(.enabled)
            SetupHelp(text: String(localized: "Free software under the GNU General Public License, version 3 or (at your option) any later version. It comes with ABSOLUTELY NO WARRANTY."))
            WeightedRow(spacing: 8) {
                LinkKey(label: String(localized: "SOURCE CODE"), url: Links.source)
                LinkKey(label: "GPL-3.0", url: Links.gpl)
            }
            SetupHeading(text: String(localized: "PRIVACY"))
            SetupHelp(text: String(localized: "Dic2Phone collects nothing. No account, no ads, no analytics, no telemetry, no crash reports: nothing about you or your recordings is ever sent to the developer or to anyone else. The app works fully offline."))
            howMade
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    @ViewBuilder
    private var howMade: some View {
        Button {
            keyClick()
            withAnimation { showingHowMade.toggle() }
        } label: {
            SetupHeading(text: "\(showingHowMade ? Glyph.unfolded : Glyph.folded)  \(String(localized: "MADE WITH AI"))")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if showingHowMade {
            SetupHelp(text: String(localized: "Dic2Phone was designed, directed and tested by WolfyD, and much of its code was written with an AI coding assistant (Claude, by Anthropic). Like any software it can have bugs: reports are welcome on GitHub."))
        }
    }
}
