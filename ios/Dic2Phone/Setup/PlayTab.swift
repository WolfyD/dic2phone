import SwiftUI

/// Playback speed, whether a faster tape sounds higher, and skipping silences.
struct PlayTab: View {
    @Environment(Settings.self) private var settings

    var body: some View {
        SetupPanel(title: String(localized: "PLAYBACK")) {
            SetupHeading(text: String(localized: "SPEED"))
            ChoiceKeys(
                labels: Settings.playSpeeds.map { "\($0.formatted())×" },
                chosen: Settings.playSpeeds.firstIndex(of: settings.playSpeed) ?? 0
            ) { settings.playSpeed = Settings.playSpeeds[$0] }
            SetupHeading(text: String(localized: "PITCH"))
            ChoiceKeys(
                labels: [String(localized: "NATURAL"), String(localized: "TAPE")],
                chosen: settings.tapePitch ? 1 : 0
            ) { settings.tapePitch = $0 == 1 }
            SetupHelp(text: String(localized: "NATURAL keeps voices at their own pitch at any speed. TAPE works like a real deck: faster sounds higher, slower sounds deeper."))
            SetupToggle(
                title: String(localized: "SKIP SILENCE"),
                help: String(localized: "Jump over long quiet stretches (over a second) while playing. The tape itself isn't changed."),
                isOn: settings.skipSilence
            ) { settings.skipSilence.toggle() }
        }
    }
}
