import CoreGraphics

/// A repeatable random sequence (SplitMix64): synthesized sounds come out the same every
/// launch, and handwriting doesn't jitter on redraw.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// Seeded from the text itself (FNV-1a). Swift's own string hashes change every launch.
    init(text: String) {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3
        }
        state = hash
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    mutating func unit() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }

    /// Uniform in 0..<1, for drawing.
    mutating func fraction() -> CGFloat {
        CGFloat(unit())
    }

    /// Uniform in -1..<1.
    mutating func signed() -> Float {
        unit() * 2 - 1
    }
}
