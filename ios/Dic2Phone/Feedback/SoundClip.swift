/// A short mono 16-bit sound, held in memory.
struct SoundClip: Sendable {
    let samples: [Int16]
    let sampleRate: Int

    /// Clamps to -1...1, then scales to 16 bits at `fullScale`.
    init(_ signal: [Float], sampleRate: Int, fullScale: Float) {
        self.samples = signal.map { Int16(min(max($0, -1), 1) * fullScale) }
        self.sampleRate = sampleRate
    }
}
