/// The deck's one-shot sounds, and how loud each plays.
enum DeckSound: CaseIterable {
    case recStart, recStop, softKey, firmKey, eject, insert, detent, windEnd

    var volume: Float {
        switch self {
        case .recStart, .recStop, .eject, .insert: 0.5
        case .softKey, .firmKey: 0.15
        case .detent: 0.4
        case .windEnd: 0.35
        }
    }

    func synthesize() -> SoundClip {
        switch self {
        case .recStart: SynthSounds.recStart()
        case .recStop: SynthSounds.recStop()
        case .softKey: SynthSounds.key(variant: 1)
        case .firmKey: SynthSounds.key(variant: 2)
        case .eject: SynthSounds.eject()
        case .insert: SynthSounds.insert()
        case .detent: SynthSounds.detent()
        case .windEnd: SynthSounds.recStop()
        }
    }
}
