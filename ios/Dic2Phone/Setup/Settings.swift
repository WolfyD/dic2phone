import Foundation
import Observation

/// The user's choices, kept in UserDefaults under the same keys as the Android app's preferences.
@MainActor
@Observable
final class Settings {
    static let labelLimit = 40
    static let playSpeeds: [Float] = [0.75, 1, 1.25, 1.5, 2]
    static let voxSensitivities = 0...2
    private static let maxTapeSecondsRange = 10...3600

    @ObservationIgnored private let defaults: UserDefaults

    var sounds: Bool { didSet { defaults.set(sounds, forKey: Key.sounds) } }
    var hiss: Bool { didSet { defaults.set(hiss, forKey: Key.hiss) } }
    var themeID: String { didSet { defaults.set(themeID, forKey: Key.theme) } }
    var snapToFlag: Bool { didSet { defaults.set(snapToFlag, forKey: Key.snap) } }
    var vox: Bool { didSet { defaults.set(vox, forKey: Key.vox) } }
    var voxSensitivity: Int { didSet { defaults.set(voxSensitivity, forKey: Key.voxSensitivity) } }
    var playSpeed: Float { didSet { defaults.set(playSpeed, forKey: Key.playSpeed) } }
    var tapePitch: Bool { didSet { defaults.set(tapePitch, forKey: Key.tapePitch) } }
    var skipSilence: Bool { didSet { defaults.set(skipSilence, forKey: Key.skipSilence) } }
    var tapeWind: Bool { didSet { defaults.set(tapeWind, forKey: Key.tapeWind) } }
    var windCue: Bool { didSet { defaults.set(windCue, forKey: Key.windCue) } }
    /// AUTO-TIDY's days, one of `AutoTidy.choices`; 0 is off.
    var tidyDays: Int { didSet { defaults.set(tidyDays, forKey: Key.tidyDays) } }
    /// The effects baked into copies to send, and heard when `playWithEffects` is on.
    var effects: TapeEffects { didSet { saveEffects() } }
    var playWithEffects: Bool { didSet { defaults.set(playWithEffects, forKey: Key.playWithEffects) } }
    /// One of `EffectCopies.keepChoices`.
    var effectKeepDays: Int { didSet { defaults.set(effectKeepDays, forKey: Key.effectKeepDays) } }
    var deckSort: TapeSort { didSet { defaults.set(deckSort.rawValue, forKey: Key.deckSort) } }
    var shelfSort: TapeSort { didSet { defaults.set(shelfSort.rawValue, forKey: Key.shelfSort) } }
    var vaultSort: TapeSort { didSet { defaults.set(vaultSort.rawValue, forKey: Key.vaultSort) } }
    var deckTape: TapeID? { didSet { defaults.set(deckTape?.fileName ?? "", forKey: Key.deckTape) } }
    var minidisc: Bool { didSet { defaults.set(minidisc, forKey: Key.minidisc) } }
    /// WHERE RECORDED.
    var notesPlace: Bool { didSet { defaults.set(notesPlace, forKey: Key.location) } }
    var labelTyped: Bool { didSet { defaults.set(labelTyped, forKey: Key.labelTyped) } }
    /// Nil until one is picked: the first request for captions asks which.
    var speechModel: SpeechModel? { didSet { defaults.set(speechModel?.rawValue ?? "", forKey: Key.speechModel) } }
    var captionLanguage: String { didSet { defaults.set(captionLanguage, forKey: Key.captionLanguage) } }
    var autoCaptions: AutoCaptions { didSet { defaults.set(autoCaptions.rawValue, forKey: Key.autoCaptions) } }
    private(set) var tapeLabel: String

    init(defaults: UserDefaults) {
        self.defaults = defaults
        sounds = defaults.object(forKey: Key.sounds) as? Bool ?? true
        hiss = defaults.object(forKey: Key.hiss) as? Bool ?? true
        themeID = defaults.string(forKey: Key.theme) ?? Themes.walnut.id
        snapToFlag = defaults.object(forKey: Key.snap) as? Bool ?? true
        vox = defaults.bool(forKey: Key.vox)
        let storedSensitivity = defaults.object(forKey: Key.voxSensitivity) as? Int ?? 1
        voxSensitivity = Settings.voxSensitivities.contains(storedSensitivity) ? storedSensitivity : 1
        let storedSpeed = defaults.object(forKey: Key.playSpeed) as? Float ?? 1
        playSpeed = Settings.playSpeeds.contains(storedSpeed) ? storedSpeed : 1
        tapePitch = defaults.bool(forKey: Key.tapePitch)
        skipSilence = defaults.bool(forKey: Key.skipSilence)
        tapeWind = defaults.bool(forKey: Key.tapeWind)
        windCue = defaults.bool(forKey: Key.windCue)
        let storedTidyDays = defaults.integer(forKey: Key.tidyDays)
        tidyDays = AutoTidy.choices.contains(storedTidyDays) ? storedTidyDays : 0
        effects = TapeEffects(
            hiss: defaults.object(forKey: Key.effectHiss) as? Bool ?? true,
            muffle: defaults.object(forKey: Key.effectMuffle) as? Bool ?? true,
            wow: defaults.object(forKey: Key.effectWow) as? Bool ?? true,
            saturate: defaults.object(forKey: Key.effectSaturate) as? Bool ?? true
        )
        playWithEffects = defaults.bool(forKey: Key.playWithEffects)
        let storedKeepDays = defaults.integer(forKey: Key.effectKeepDays)
        effectKeepDays = EffectCopies.keepChoices.contains(storedKeepDays) ? storedKeepDays : 0
        deckSort = TapeSort(rawValue: defaults.string(forKey: Key.deckSort) ?? "") ?? .newest
        shelfSort = TapeSort(rawValue: defaults.string(forKey: Key.shelfSort) ?? "") ?? .newest
        vaultSort = TapeSort(rawValue: defaults.string(forKey: Key.vaultSort) ?? "") ?? .newest
        deckTape = defaults.string(forKey: Key.deckTape).flatMap(TapeID.init)
        minidisc = defaults.bool(forKey: Key.minidisc)
        notesPlace = defaults.bool(forKey: Key.location)
        labelTyped = defaults.bool(forKey: Key.labelTyped)
        speechModel = SpeechModel(rawValue: defaults.string(forKey: Key.speechModel) ?? "")
        let storedLanguage = defaults.string(forKey: Key.captionLanguage) ?? ""
        captionLanguage = CaptionLanguage.codes.contains(storedLanguage) ? storedLanguage : CaptionLanguage.automatic
        autoCaptions = AutoCaptions(rawValue: defaults.integer(forKey: Key.autoCaptions)) ?? .off
        tapeLabel = defaults.string(forKey: Key.tapeLabel) ?? ""
    }

    var theme: Palette {
        Themes.palette(id: themeID)
    }

    /// The effects to play tapes through; nil if they play as recorded.
    var playingEffects: TapeEffects? {
        playWithEffects && effects.any ? effects : nil
    }

    /// Tapes roll onto a new one after this long. Normally an hour; UI tests shorten it with a
    /// `-debug_max_tape_s` launch argument, which lands in UserDefaults' argument domain.
    var maxTapeMs: Int64 {
        let range = Self.maxTapeSecondsRange
        let stored = defaults.integer(forKey: Key.maxTapeSeconds)
        let seconds = stored == 0 ? range.upperBound : min(max(stored, range.lowerBound), range.upperBound)
        return Int64(seconds) * 1000
    }

    func setTapeLabel(_ text: String) {
        tapeLabel = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.labelLimit))
        defaults.set(tapeLabel, forKey: Key.tapeLabel)
    }

    func sort(for rack: Rack) -> TapeSort {
        switch rack {
        case .deck: deckSort
        case .shelf: shelfSort
        case .vault: vaultSort
        }
    }

    func cycleSort(for rack: Rack) {
        switch rack {
        case .deck: deckSort = deckSort.next
        case .shelf: shelfSort = shelfSort.next
        case .vault: vaultSort = vaultSort.next
        }
    }

    private func saveEffects() {
        defaults.set(effects.hiss, forKey: Key.effectHiss)
        defaults.set(effects.muffle, forKey: Key.effectMuffle)
        defaults.set(effects.wow, forKey: Key.effectWow)
        defaults.set(effects.saturate, forKey: Key.effectSaturate)
    }

    private enum Key {
        static let sounds = "sounds"
        static let hiss = "hiss"
        static let theme = "theme"
        static let snap = "snap"
        static let vox = "vox"
        static let voxSensitivity = "vox_sens"
        static let playSpeed = "play_speed"
        static let tapePitch = "tape_pitch"
        static let skipSilence = "skip_silence"
        static let tapeWind = "tape_wind"
        static let windCue = "wind_cue"
        static let tidyDays = "tidy_days"
        static let effectHiss = "fx_hiss"
        static let effectMuffle = "fx_muffle"
        static let effectWow = "fx_wow"
        static let effectSaturate = "fx_sat"
        static let playWithEffects = "fx_play"
        static let effectKeepDays = "fx_keep_days"
        static let deckSort = "sort_deck"
        static let shelfSort = "sort_shelf"
        static let vaultSort = "sort_vault"
        static let deckTape = "deck_tape"
        static let tapeLabel = "tape_label"
        static let minidisc = "minidisc"
        static let labelTyped = "label_typed"
        static let location = "location"
        static let speechModel = "cc_model"
        static let captionLanguage = "cc_lang"
        static let autoCaptions = "auto_cc"
        static let maxTapeSeconds = "debug_max_tape_s"
    }
}
