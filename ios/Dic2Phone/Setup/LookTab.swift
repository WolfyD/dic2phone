import SwiftUI

/// The theme, whether the deck takes cassettes or MiniDiscs, and what's written on the label
/// and how.
struct LookTab: View {
    @Environment(Settings.self) private var settings

    @State private var writingLabel = false

    var body: some View {
        VStack(spacing: 10) {
            themePanel
            labelPanel
        }
        .labelWritingAlert(
            isPresented: $writingLabel,
            title: LabelWritingAlert.labelTitle(minidisc: settings.minidisc),
            original: settings.tapeLabel,
            placeholder: String(localized: "e.g. NOTES or MIXTAPE '89"),
            limit: Settings.labelLimit,
            hint: String(localized: "Leave empty for a blank label"),
            onWrite: settings.setTapeLabel
        )
    }

    private var themePanel: some View {
        SetupPanel(title: String(localized: "COLOUR THEME")) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Themes.all) { theme in
                        ThemeCard(theme: theme, loaded: theme.id == settings.themeID) {
                            settings.themeID = theme.id
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var labelPanel: some View {
        let label = settings.tapeLabel.isEmpty ? String(localized: "(blank)") : settings.tapeLabel
        return SetupPanel(title: String(localized: "IN THE DECK")) {
            ChoiceKeys(
                labels: [String(localized: "CASSETTE"), String(localized: "MINIDISC")],
                chosen: settings.minidisc ? 1 : 0
            ) { settings.minidisc = $0 == 1 }
            SetupHelp(text: String(localized: "Label: \(label)"))
            SetupHelp(text: labelHelp)
            DeckKey(label: String(localized: "WRITE LABEL"), height: 40) { writingLabel = true }
            SetupHeading(text: String(localized: "LABEL WRITING"))
            ChoiceKeys(
                labels: [String(localized: "HANDWRITTEN"), String(localized: "TYPED")],
                chosen: settings.labelTyped ? 1 : 0
            ) { settings.labelTyped = $0 == 1 }
            CartridgeView(
                label: .sample(userLabel: settings.tapeLabel, disc: settings.minidisc),
                spinning: false, progress: 0.3, typed: settings.labelTyped
            )
            .frame(maxWidth: 220)
                .frame(maxWidth: .infinity)
            SetupHelp(text: String(localized: "How your writing looks on the label and on tape titles: pen, or a typewriter."))
        }
    }

    private var labelHelp: String {
        settings.minidisc
            ? String(localized: "What's written on the disc in the deck, just for looks. Long-press the disc on the deck to change it too.")
            : String(localized: "What's written on the tape in the deck, just for looks. Long-press the tape on the deck to change it too.")
    }
}
