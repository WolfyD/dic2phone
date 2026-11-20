/// A slow sine for wobbling something: one value per sample, between -1 and 1.
struct Oscillator {
    private var phase: Double
    private let step: Double

    /// - Parameter phase: where in the cycle it starts, 0..<1.
    init(hz: Double, sampleRate: Double, phase: Double = 0) {
        self.phase = phase
        step = hz / sampleRate
    }

    mutating func next() -> Float {
        phase += step
        if phase >= 1 { phase -= 1 }
        return WaveTable.sine.value(at: phase)
    }
}
