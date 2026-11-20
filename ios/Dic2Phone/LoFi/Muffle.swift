/// The narrow tone of a small mic and a worn head: the rumble cut, the top rolled off, and a
/// little honk in the middle.
struct Muffle {
    private var rumbleCut: Biquad
    private var rollOff: Biquad
    private var gentleRollOff: Biquad
    private var honk: Biquad

    init(sampleRate: Double) {
        rumbleCut = .highpass(sampleRate: sampleRate, hz: 160, q: 0.7)
        rollOff = .lowpass(sampleRate: sampleRate, hz: 3400, q: 0.8)
        gentleRollOff = .lowpass(sampleRate: sampleRate, hz: 5200, q: 0.6)
        honk = .peak(sampleRate: sampleRate, hz: 1300, q: 0.9, gainDb: 2.5)
    }

    mutating func process(_ sample: Float) -> Float {
        honk.filter(gentleRollOff.filter(rollOff.filter(rumbleCut.filter(sample))))
    }
}
