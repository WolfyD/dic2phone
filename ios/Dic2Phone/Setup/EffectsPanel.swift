import SwiftUI

/// TAPE EFFECTS: the old-recorder sounds baked into tapes sent WITH TAPE SOUND, and whether
/// tapes are heard through them in the app too.
struct EffectsPanel: View {
    @Environment(Settings.self) private var settings

    var body: some View {
        SetupPanel(title: String(localized: "TAPE EFFECTS")) {
            SetupHelp(text: String(localized: "Make a tape sound like it came off an old portable recorder. Your recordings stay clean: when you SEND a tape you can pick WITH TAPE SOUND, and the effects are baked into the copy that's sent."))
            SetupToggle(
                title: String(localized: "HISS & MOTOR"),
                help: String(localized: "Cheap-tape hiss and a faint transport-motor whine."),
                isOn: settings.effects.hiss
            ) { settings.effects.hiss.toggle() }
            SetupToggle(
                title: String(localized: "MUFFLED"),
                help: String(localized: "Dull, narrow tone: worn head, small mic."),
                isOn: settings.effects.muffle
            ) { settings.effects.muffle.toggle() }
            SetupToggle(
                title: String(localized: "WOW & FLUTTER"),
                help: String(localized: "Slight pitch wobble from an uneven capstan."),
                isOn: settings.effects.wow
            ) { settings.effects.wow.toggle() }
            SetupToggle(
                title: String(localized: "SATURATION"),
                help: String(localized: "Soft tape compression: loud bits squashed, quiet bits lifted."),
                isOn: settings.effects.saturate
            ) { settings.effects.saturate.toggle() }
            SetupToggle(
                title: String(localized: "PLAY WITH EFFECTS"),
                help: String(localized: "Also hear tapes through the effects when playing them in the app."),
                isOn: settings.playWithEffects,
                enabled: settings.effects.any
            ) { settings.playWithEffects.toggle() }
        }
    }
}
