import Foundation

/// The deck's sounds, synthesized. The Android app uses licensed recordings that can't be in
/// the public source; these stand-ins keep the same timing, so the haptics still line up.
enum SynthSounds {
    private static let keyRate = 24_000
    private static let hissRate = 44_100

    static func key(variant: Int) -> SoundClip {
        var signal = silence(ms: 60, rate: keyRate)
        hit(&signal, atMs: 0, gain: 0.8, hz: variant == 1 ? 1100 : 950, seed: UInt64(variant))
        return SoundClip(signal, sampleRate: keyRate, fullScale: 30_000)
    }

    /// Fingertip contact, then the latch clacking in (~82 ms).
    static func recStart() -> SoundClip {
        var signal = silence(ms: 300, rate: keyRate)
        hit(&signal, atMs: 0, gain: 0.3)
        hit(&signal, atMs: 82, gain: 1, hz: 700, decayMs: 6)
        return SoundClip(signal, sampleRate: keyRate, fullScale: 30_000)
    }

    /// STOP clacks down (~55 ms), the keys release (~185 ms), the mechanism thuds (~280 ms).
    static func recStop() -> SoundClip {
        var signal = silence(ms: 420, rate: keyRate)
        hit(&signal, atMs: 55, gain: 1, hz: 700, decayMs: 6)
        hit(&signal, atMs: 185, gain: 0.5, hz: 1000)
        hit(&signal, atMs: 280, gain: 0.8, hz: 300, decayMs: 10)
        return SoundClip(signal, sampleRate: keyRate, fullScale: 30_000)
    }

    /// Key travel (~70 ms), latch (~160 ms), the cassette popping up (~250 ms).
    static func eject() -> SoundClip {
        var signal = silence(ms: 420, rate: keyRate)
        hit(&signal, atMs: 70, gain: 0.4)
        hit(&signal, atMs: 160, gain: 0.6, hz: 800)
        hit(&signal, atMs: 250, gain: 1, hz: 400, decayMs: 9)
        return SoundClip(signal, sampleRate: keyRate, fullScale: 30_000)
    }

    /// The shell sliding in (a soft scrape), then clunking home (~360 ms).
    static func insert() -> SoundClip {
        var signal = silence(ms: 520, rate: keyRate)
        var random = SeededRandom(seed: 5)
        var lowPassed: Float = 0
        let scrapeLength = keyRate * 300 / 1000
        for i in 0..<scrapeLength {
            lowPassed += 0.1 * (random.signed() - lowPassed)
            signal[i] += lowPassed * 0.5 * Float(sin(Double.pi * Double(i) / Double(scrapeLength)))
        }
        hit(&signal, atMs: 10, gain: 0.4)
        hit(&signal, atMs: 360, gain: 1, hz: 450, decayMs: 9)
        return SoundClip(signal, sampleRate: keyRate, fullScale: 30_000)
    }

    /// A small dry plastic tick (~25 ms). Everything dies within milliseconds: long high ringing
    /// is what makes a click sound metallic.
    static func detent() -> SoundClip {
        let count = hissRate * 25 / 1000
        var random = SeededRandom(seed: 7)
        var lowPassed: Float = 0
        let signal = (0..<count).map { i -> Float in
            let t = Double(i) / Double(hissRate)
            lowPassed += 0.3 * (random.signed() - lowPassed)
            let click = lowPassed * Float(exp(-t / 0.0012))
            let body = 0.45 * Float(sin(2 * .pi * 480 * t) * exp(-t / 0.0035))
            let thump = 0.35 * Float(sin(2 * .pi * 140 * t) * exp(-t / 0.008))
            return (click * 1.1 + body + thump) * 0.7
        }
        return SoundClip(signal, sampleRate: hissRate, fullScale: 32_767)
    }

    /// A 2 s seamless loop of tape hiss with slow flutter, plus a faint 50/100 Hz motor hum.
    /// Every periodic part has whole cycles in the loop and the noise tail is cross-faded into
    /// the head, so the loop never clicks.
    static func hiss() -> SoundClip {
        let count = hissRate * 2
        let noise = loopableHiss(count: count)
        let signal = (0..<count).map { i -> Float in
            let t = Double(i) / Double(hissRate)
            let flutter = 1 + 0.18 * Float(sin(2 * .pi * 0.5 * t)) + 0.07 * Float(sin(2 * .pi * 3.5 * t))
            let hum = 0.0022 * Float(sin(2 * .pi * 50 * t)) + 0.0014 * Float(sin(2 * .pi * 100 * t))
            return noise[i] * 0.020 * flutter + hum
        }
        return SoundClip(signal, sampleRate: hissRate, fullScale: 32_767)
    }

    /// One second of motor whirr, a seamless loop: whole cycles of hum over low, rumbling noise.
    static func wind() -> SoundClip {
        let count = keyRate
        var random = SeededRandom(seed: 11)
        var lowPassed: Float = 0
        let noise = loopable(count: count, crossfade: keyRate / 10) {
            lowPassed += 0.15 * (random.signed() - lowPassed)
            return lowPassed
        }
        let signal = (0..<count).map { i -> Float in
            let t = Double(i) / Double(keyRate)
            let hum = 0.10 * Float(sin(2 * .pi * 180 * t)) + 0.05 * Float(sin(2 * .pi * 360 * t))
            return min(max(noise[i] * 0.6 + hum, -1), 1)
        }
        return SoundClip(signal, sampleRate: keyRate, fullScale: 30_000)
    }

    /// Mostly-highs noise: rumble removed, the very top softened around 9 kHz.
    private static func loopableHiss(count: Int) -> [Float] {
        var random = SeededRandom(seed: 42)
        var rumble: Float = 0
        var softened: Float = 0
        return loopable(count: count, crossfade: hissRate / 10) {
            let white = random.signed()
            rumble += 0.08 * (white - rumble)
            softened += 0.55 * (white - rumble - softened)
            return softened
        }
    }

    /// `count` samples of noise that loop seamlessly: the overrun past `count` is cross-faded
    /// into the start.
    private static func loopable(count: Int, crossfade: Int, next: () -> Float) -> [Float] {
        var noise = (0..<(count + crossfade)).map { _ in next() }
        for i in 0..<crossfade {
            let fadeIn = Float(i) / Float(crossfade)
            noise[i] = noise[i] * fadeIn + noise[count + i] * (1 - fadeIn)
        }
        return Array(noise.prefix(count))
    }

    private static func silence(ms: Int, rate: Int) -> [Float] {
        [Float](repeating: 0, count: rate * ms / 1000)
    }

    /// A mechanical hit at `atMs`: a noise click, a short body at `hz`, and a low thump.
    private static func hit(
        _ signal: inout [Float],
        atMs: Int,
        gain: Float,
        hz: Double = 900,
        decayMs: Double = 4,
        seed: UInt64? = nil
    ) {
        var random = SeededRandom(seed: seed ?? UInt64(atMs))
        var lowPassed: Float = 0
        let start = keyRate * atMs / 1000
        let length = min(keyRate / 20, signal.count - start)
        guard length > 0 else { return }
        for i in 0..<length {
            let t = Double(i) / Double(keyRate)
            lowPassed += 0.35 * (random.signed() - lowPassed)
            let click = lowPassed * Float(exp(-t / 0.0015))
            let body = 0.5 * Float(sin(2 * .pi * hz * t) * exp(-t / (decayMs / 1000)))
            let thump = 0.4 * Float(sin(2 * .pi * 120 * t) * exp(-t / 0.012))
            signal[start + i] += gain * (click + body + thump)
        }
    }
}
