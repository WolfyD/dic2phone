import SwiftUI

/// AUTO-TIDY: how many days heard deck tapes are kept for, or never deleted.
struct TidyPanel: View {
    @Environment(Settings.self) private var settings

    var body: some View {
        SetupPanel(title: String(localized: "AUTO-TIDY")) {
            ChoiceKeys(
                labels: AutoTidy.choices.map(Self.label),
                chosen: AutoTidy.choices.firstIndex(of: settings.tidyDays) ?? 0
            ) { settings.tidyDays = AutoTidy.choices[$0] }
            SetupHelp(text: String(localized: "Deletes deck tapes you've already heard after this many days. Kept: unheard tapes, tapes with a title or flags, the tape in the deck, and everything on the shelf or in the vault. \(AutoTidy.warningDays) days before, the deck shows a warning and the tapes are marked ✂ in the list."))
        }
    }

    private static func label(_ days: Int) -> String {
        days == 0 ? String(localized: "OFF") : String(localized: "\(days)D")
    }
}
