/// Gives a tape the sound of an old portable recorder, a run of samples at a time. It carries
/// its state from one run to the next, so a whole tape goes through the same one.
///
/// The levels and frequencies were tuned by ear in the Android app and are kept the same here,
/// so a tape sounds alike from either app.
struct TapeProcessor {
    private let effects: TapeEffects
    private var wowAndFlutter: WowAndFlutter
    private var hiss: Hiss
    private var muffle: Muffle

    init(effects: TapeEffects, sampleRate: Double) {
        self.effects = effects
        wowAndFlutter = WowAndFlutter(sampleRate: sampleRate)
        hiss = Hiss(sampleRate: sampleRate)
        muffle = Muffle(sampleRate: sampleRate)
    }

    mutating func process(_ samples: inout [Float]) {
        for index in samples.indices {
            samples[index] = processed(samples[index])
        }
    }

    /// The order matters: the hiss goes on after the saturation, as it would on tape, and the
    /// muffle dulls it along with the voice.
    private mutating func processed(_ input: Float) -> Float {
        var sample = input
        if effects.wow { sample = wowAndFlutter.process(sample) }
        if effects.saturate { sample = Self.saturated(sample) }
        if effects.hiss { sample = hiss.added(to: sample) }
        if effects.muffle { sample = muffle.process(sample) }
        return sample
    }

    /// Half of tanh(3x): loud bits squashed, quiet ones lifted by half. The rational form is
    /// a cheap stand-in for tanh that meets ±1 exactly at ±3, run on every sample.
    static func saturated(_ sample: Float) -> Float {
        let x = min(max(3 * sample, -3), 3)
        return x * (27 + x * x) / (27 + 9 * x * x) / 2
    }
}
