import SwiftUI

/// How recording behaves, and the deck's own sounds.
struct RecTab: View {
    @Environment(Settings.self) private var settings
    @Environment(Locator.self) private var locator

    var body: some View {
        VStack(spacing: 10) {
            recordingPanel
            MicPanel()
            soundPanel
        }
    }

    private var recordingPanel: some View {
        SetupPanel(title: String(localized: "RECORDING")) {
            SetupHelp(text: String(localized: "Lock REC on: tap REC on the deck and it keeps recording until you tap it once more. Long sessions are cut into one-hour tapes."))
            SetupToggle(
                title: String(localized: "SNAP TO FLAG"),
                help: String(localized: "Snap your fingers while recording to flag the moment. The FLAG key does the same. Jump between flags when playing the tape in the deck."),
                isOn: settings.snapToFlag
            ) { settings.snapToFlag.toggle() }
            SetupToggle(
                title: String(localized: "NOISE-ACTIVATED"),
                help: String(localized: "When REC is locked on, silence is left off the tape. Each cut keeps a short gap so you can hear where it was. Holding REC always records everything."),
                isOn: settings.vox
            ) { settings.vox.toggle() }
            if settings.vox {
                voxSensitivity
            }
            whereRecorded
        }
    }

    @ViewBuilder
    private var whereRecorded: some View {
        SetupToggle(
            title: String(localized: "WHERE RECORDED"),
            help: String(localized: "Note the place in each tape's info (coordinates and a place name). It stays on this iPhone and isn't put in the files you send. The place name is looked up with Apple's map service."),
            isOn: settings.notesPlace && locator.isAllowed
        ) { toggleWhereRecorded() }
        if settings.notesPlace, locator.isRefused {
            SetupHelp(text: String(localized: "Location access is off, so tapes won't get a place. Turn it on in Settings › Dic2Phone › Location."), warning: true)
        }
    }

    /// Location is asked for only now, when the user first wants it. Refused, the toggle stays
    /// off and says why; allowed later in the Settings app, it comes on by itself.
    private func toggleWhereRecorded() {
        settings.notesPlace.toggle()
        if settings.notesPlace {
            Task { _ = await locator.requestPermission() }
        }
    }

    @ViewBuilder
    private var voxSensitivity: some View {
        ChoiceKeys(
            labels: [String(localized: "LOW"), String(localized: "MED"), String(localized: "HIGH")],
            chosen: settings.voxSensitivity
        ) { settings.voxSensitivity = $0 }
        SetupHelp(text: String(localized: "Sensitivity: HIGH starts on quieter sounds (whispers, a far-off voice); LOW needs louder sound and ignores more background noise."))
    }

    private var soundPanel: some View {
        SetupPanel(title: String(localized: "SOUND")) {
            SetupToggle(
                title: String(localized: "DECK SOUNDS"),
                help: String(localized: "Key clicks and cassette sounds. They stay quiet while recording, so they never end up on the tape."),
                isOn: settings.sounds
            ) { settings.sounds.toggle() }
            SetupToggle(
                title: String(localized: "REC HISS"),
                help: String(localized: "A very faint tape hiss while recording, just for the feel. Kept low enough that the mic barely hears it (a bit louder in headphones, where it can't leak onto the tape)."),
                isOn: settings.hiss && settings.sounds,
                enabled: settings.sounds
            ) { settings.hiss.toggle() }
        }
    }
}
