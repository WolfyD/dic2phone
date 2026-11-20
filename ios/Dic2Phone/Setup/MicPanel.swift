import SwiftUI

/// MICROPHONE: AUTO, or one of the mics connected now.
struct MicPanel: View {
    @Environment(MicChooser.self) private var chooser

    var body: some View {
        SetupPanel(title: String(localized: "MICROPHONE")) {
            VStack(spacing: 6) {
                choice(String(localized: "AUTO"), key: "")
                ForEach(chooser.microphones) { microphone in
                    choice(microphone.label, key: microphone.key)
                }
            }
            SetupHelp(text: String(localized: "AUTO lets the iPhone choose. A plugged-in, USB or Bluetooth mic is remembered and used whenever it's connected; without it, the iPhone's own mic records. A Bluetooth headset records, and plays, in phone-call quality while recording."))
            if chooser.chosenIsMissing {
                SetupHelp(text: String(localized: "The chosen mic isn't connected right now."), warning: true)
            }
        }
        .task { await chooser.watch() }
    }

    private func choice(_ label: String, key: String) -> some View {
        let chosen = chooser.chosen == key
        return DeckKey(label: chosen ? "\(Glyph.chosen) \(label)" : label, height: 40) { chooser.choose(key) }
            .accessibilityLabel(Text(verbatim: label))
            .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
