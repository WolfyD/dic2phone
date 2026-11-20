/// Cheap-tape hiss, the faint whine of a transport motor that drifts with its speed, and a
/// touch of mains hum.
struct Hiss {
    private static let motorHz = 118.0
    private static let mainsHz = 50.0

    private let sampleRate: Double
    /// Seeded, so a tape's copy comes out the same every time it's made.
    private var random = SeededRandom(seed: 1984)
    private var lowNoise: Float = 0
    private var hiss: Float = 0
    private var hissSwell: Oscillator
    private var motorDrift: Oscillator
    private var mains: Oscillator
    private var motorPhase = 0.0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        hissSwell = Oscillator(hz: 0.5, sampleRate: sampleRate)
        motorDrift = Oscillator(hz: 0.7, sampleRate: sampleRate)
        mains = Oscillator(hz: Self.mainsHz, sampleRate: sampleRate)
    }

    mutating func added(to sample: Float) -> Float {
        sample + nextHiss() + nextMotorWhine() + 0.0018 * mains.next()
    }

    /// White noise with its lows taken out, then its harshest highs: what's left is the soft
    /// "sss" of tape rather than radio static.
    private mutating func nextHiss() -> Float {
        let white = random.signed()
        lowNoise += 0.07 * (white - lowNoise)
        hiss += 0.6 * ((white - lowNoise) - hiss)
        return hiss * 0.016 * (1 + 0.2 * hissSwell.next())
    }

    private mutating func nextMotorWhine() -> Float {
        motorPhase += Self.motorHz * (1 + 0.012 * Double(motorDrift.next())) / sampleRate
        if motorPhase >= 1 { motorPhase -= 1 }
        return WaveTable.buzz.value(at: motorPhase) * 0.0016
    }
}
