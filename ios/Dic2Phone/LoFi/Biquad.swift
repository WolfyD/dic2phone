import Foundation

/// A two-pole filter, with the coefficients from Robert Bristow-Johnson's Audio EQ Cookbook.
struct Biquad {
    private let b0, b1, b2, a1, a2: Double
    private var z1 = 0.0
    private var z2 = 0.0

    private init(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) {
        self.b0 = b0 / a0
        self.b1 = b1 / a0
        self.b2 = b2 / a0
        self.a1 = a1 / a0
        self.a2 = a2 / a0
    }

    static func lowpass(sampleRate: Double, hz: Double, q: Double) -> Biquad {
        let (cosine, alpha) = shape(sampleRate: sampleRate, hz: hz, q: q)
        return Biquad(
            b0: (1 - cosine) / 2, b1: 1 - cosine, b2: (1 - cosine) / 2,
            a0: 1 + alpha, a1: -2 * cosine, a2: 1 - alpha
        )
    }

    static func highpass(sampleRate: Double, hz: Double, q: Double) -> Biquad {
        let (cosine, alpha) = shape(sampleRate: sampleRate, hz: hz, q: q)
        return Biquad(
            b0: (1 + cosine) / 2, b1: -(1 + cosine), b2: (1 + cosine) / 2,
            a0: 1 + alpha, a1: -2 * cosine, a2: 1 - alpha
        )
    }

    static func peak(sampleRate: Double, hz: Double, q: Double, gainDb: Double) -> Biquad {
        let (cosine, alpha) = shape(sampleRate: sampleRate, hz: hz, q: q)
        let gain = pow(10, gainDb / 40)
        return Biquad(
            b0: 1 + alpha * gain, b1: -2 * cosine, b2: 1 - alpha * gain,
            a0: 1 + alpha / gain, a1: -2 * cosine, a2: 1 - alpha / gain
        )
    }

    mutating func filter(_ sample: Float) -> Float {
        let x = Double(sample)
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return Float(y)
    }

    private static func shape(sampleRate: Double, hz: Double, q: Double) -> (cosine: Double, alpha: Double) {
        let omega = 2 * Double.pi * hz / sampleRate
        return (cos(omega), sin(omega) / (2 * q))
    }
}
