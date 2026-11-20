import Foundation

/// Finger-snap (or clap) detector, used to flag a moment hands-free.
///
/// A snap is a crack: high-frequency energy jumps 25 dB or more out of quiet within ~6 ms, is
/// down 15 dB again ~35 ms later and back near the background by ~70 ms, with little
/// low-frequency body, and it stands alone: a quarter second of quiet before it and ~150 ms
/// after. Speech fails on the body test (vowels) and on standing alone ("t", "k", "ch" sit
/// inside words), knocks fail the high-frequency test, music and noise the sudden-onset test.
struct SnapDetector {
    private static let blockSize = 256                // 5.8 ms at 44.1 kHz
    private static let highPassCoefficient: Float = 0.75  // one-pole high-pass at about 2.3 kHz
    private static let refractoryBlocks = 260         // about 1.5 s between snaps
    private static let quietBeforeBlocks = 43         // about 250 ms of quiet before the crack
    private static let settledBlock = 12              // about 70 ms: the crack is gone
    private static let quietAfterBlock = 26           // about 150 ms: nobody went on talking

    private var highPassOut: Float = 0
    private var highPassIn: Float = 0
    private var backgroundHighDb: Float = -70
    private var backgroundAllDb: Float = -70
    private var previousHighDb: Float = -90
    private var blocksSinceOnset = -1
    private var onsetPeakDb: Float = -90
    private var cooldown = 0
    private var quietBlocks = 0
    private var block: [Float] = []

    /// - Returns: true when a snap was confirmed somewhere in `chunk`.
    mutating func feed(_ chunk: [Int16]) -> Bool {
        var confirmed = false
        for sample in chunk {
            block.append(Float(sample))
            if block.count == Self.blockSize {
                if analyzeBlock() { confirmed = true }
                block.removeAll(keepingCapacity: true)
            }
        }
        return confirmed
    }

    private mutating func analyzeBlock() -> Bool {
        var energyAll = 0.0
        var energyHigh = 0.0
        for x in block {
            highPassOut = Self.highPassCoefficient * (highPassOut + x - highPassIn)
            highPassIn = x
            energyAll += Double(x) * Double(x)
            energyHigh += Double(highPassOut) * Double(highPassOut)
        }
        let fullScale = 32768.0 * 32768.0 * Double(Self.blockSize)
        let allDb = Float(10 * log10(energyAll / fullScale + 1e-12))
        let highDb = Float(10 * log10(energyHigh / fullScale + 1e-12))

        if cooldown > 0 { cooldown -= 1 }
        var confirmed = false
        if blocksSinceOnset < 0 {
            if isOnset(highDb: highDb, energyHigh: energyHigh, energyAll: energyAll) {
                blocksSinceOnset = 0
                onsetPeakDb = highDb
            } else {
                adaptBackground(highDb: highDb, allDb: allDb)
            }
        } else {
            confirmed = followCandidate(highDb: highDb, allDb: allDb)
        }
        let nearBackground = allDb < backgroundAllDb + 8 && highDb < backgroundHighDb + 10
        quietBlocks = nearBackground ? quietBlocks + 1 : 0
        previousHighDb = highDb
        return confirmed
    }

    private func isOnset(highDb: Float, energyHigh: Double, energyAll: Double) -> Bool {
        cooldown == 0
            && quietBlocks >= Self.quietBeforeBlocks
            && highDb > backgroundHighDb + 25
            && highDb > -38
            && previousHighDb < backgroundHighDb + 10
            && energyHigh > 0.45 * energyAll
    }

    private mutating func adaptBackground(highDb: Float, allDb: Float) {
        backgroundHighDb += (highDb - backgroundHighDb) * (highDb < backgroundHighDb ? 0.1 : 0.01)
        backgroundAllDb += (allDb - backgroundAllDb) * (allDb < backgroundAllDb ? 0.1 : 0.01)
    }

    private mutating func followCandidate(highDb: Float, allDb: Float) -> Bool {
        blocksSinceOnset += 1
        let n = blocksSinceOnset
        if n <= 1 { onsetPeakDb = max(onsetPeakDb, highDb) }
        if n == 6 {
            if highDb > onsetPeakDb - 15 { blocksSinceOnset = -1 }
        } else if n == Self.settledBlock {
            let settled = highDb < backgroundHighDb + 12 && allDb < backgroundAllDb + 15
            if !settled { blocksSinceOnset = -1 }
        } else if n > Self.settledBlock, n <= Self.quietAfterBlock {
            // After the crack it must stay quiet a little; speech carries on into a vowel.
            if allDb > backgroundAllDb + 12 {
                blocksSinceOnset = -1
            } else if n == Self.quietAfterBlock {
                cooldown = Self.refractoryBlocks
                blocksSinceOnset = -1
                return true
            }
        }
        return false
    }
}
