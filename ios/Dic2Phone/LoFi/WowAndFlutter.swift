/// The pitch wobble of an uneven capstan. The sound runs through a short delay whose length
/// sways: wow is the slow sway (about 0.3 % in pitch), flutter the fast shimmer on top.
struct WowAndFlutter {
    /// A power of two, so indices wrap with a mask; far longer than the longest delay.
    private static let ringSize = 16_384

    private let sampleRate: Double
    private var ring = [Float](repeating: 0, count: ringSize)
    private var writeIndex = 0
    private var slowWow: Oscillator
    private var slowerWow: Oscillator
    private var flutter: Oscillator
    private var fastFlutter: Oscillator

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        slowWow = Oscillator(hz: 0.55, sampleRate: sampleRate)
        slowerWow = Oscillator(hz: 0.23, sampleRate: sampleRate, phase: 0.2)
        flutter = Oscillator(hz: 6.3, sampleRate: sampleRate)
        fastFlutter = Oscillator(hz: 11.7, sampleRate: sampleRate, phase: 0.1)
    }

    mutating func process(_ sample: Float) -> Float {
        let mask = Self.ringSize - 1
        ring[writeIndex] = sample
        let position = Double(writeIndex) - delaySeconds() * sampleRate
        let index = Int(position.rounded(.down))
        let fraction = Float(position - Double(index))
        let before = ring[index & mask]
        let after = ring[(index + 1) & mask]
        writeIndex = (writeIndex + 1) & mask
        return before + (after - before) * fraction
    }

    /// The four rates don't divide into each other, so the wobble never audibly repeats.
    private mutating func delaySeconds() -> Double {
        let sway = 0.00085 * slowWow.next() + 0.00045 * slowerWow.next()
            + 0.000026 * flutter.next() + 0.000012 * fastFlutter.next()
        return 0.006 + Double(sway)
    }
}
