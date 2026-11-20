import SwiftUI

/// An on/off setting: a lamp and its name, what it does, and a key that flips it.
struct SetupToggle: View {
    let title: String
    let help: String
    let isOn: Bool
    var enabled = true
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Led(on: isOn)
                    SetupHeading(text: title)
                }
                SetupHelp(text: help)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(enabled ? 1 : 0.45)
            DeckKey(label: isOn ? String(localized: "ON") : String(localized: "OFF"), height: 40, action: onToggle)
                .frame(width: 72)
                .accessibilityLabel(Text(verbatim: title))
                .accessibilityValue(isOn ? Text("On") : Text("Off"))
        }
        .disabled(!enabled)
    }
}
