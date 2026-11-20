import SwiftUI

/// The fonts and frameworks the app is built from, with their licenses.
struct CreditsPanel: View {
    var body: some View {
        SetupPanel(title: String(localized: "CREDITS")) {
            SetupHeading(text: String(localized: "LABEL HANDWRITING"))
            SetupHelp(text: String(localized: "Reenie Beanie by James Grieshaber, licensed under the SIL Open Font License 1.1."))
            SetupHeading(text: String(localized: "TYPEFACE"))
            SetupHelp(text: String(localized: "Courier Prime, Copyright 2015 The Courier Prime Project Authors. Barlow (the badge), Copyright 2017 The Barlow Project Authors. Both licensed under the SIL Open Font License 1.1."))
            LinkKey(label: String(localized: "OPEN FONT LICENSE"), url: Links.openFontLicense)
            SetupHeading(text: String(localized: "SOFTWARE"))
            SetupHelp(text: String(localized: "Built with Swift and SwiftUI. The deck's sounds are made by the app itself."))
        }
    }
}
