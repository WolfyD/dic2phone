import Foundation

/// Noise-activated recording: decides which chunks reach the tape.
///
/// Each skipped silence leaves `tail` + `preRoll` (about 1.15 s) of quiet behind, so a listener
/// can hear there was a cut and lines don't run into each other. Pauses shorter than
/// `maxPause` are kept whole.
struct NoiseGate {
    static let preRoll = TapeFormat.sampleRate * 40 / 100
    static let tail = TapeFormat.sampleRate * 75 / 100
    static let maxPause = TapeFormat.sampleRate * 3 / 2
    static let fadeLength = TapeFormat.sampleRate / 50
    static let thresholdsDb: [Float] = [-36, -45, -53]

    var gated: Bool
    private(set) var rolling: Bool
    private(set) var cuts = 0
    private(set) var skippedSamples = 0
    private(set) var pendingCount = 0

    private let thresholdDb: Float
    private var pending: [[Int16]] = []
    private var ring: [[Int16]] = []
    private var ringCount = 0
    private var loudBits = 0
    private var floorDb: Float = -60

    init(gated: Bool, sensitivity: Int) {
        self.gated = gated
        self.rolling = !gated
        let index = min(max(sensitivity, 0), Self.thresholdsDb.count - 1)
        self.thresholdDb = Self.thresholdsDb[index]
    }

    /// - Returns: the chunks to write to the tape now, in order.
    mutating func feed(_ chunk: [Int16], rmsDb: Float, tapeHasAudio: Bool) -> [[Int16]] {
        let loud = trackLoudness(rmsDb)
        if !gated {
            var writes: [[Int16]] = []
            if !rolling {
                rolling = true
                writes += flushRing(fadeIn: true)
            }
            return writes + flushPending() + [chunk]
        }
        return rolling ? feedWhileRolling(chunk, loud: loud) : feedWhileWaiting(chunk, tapeHasAudio: tapeHasAudio)
    }

    /// The natural tail of a pause still being held back, for when recording stops.
    mutating func drainTail() -> [[Int16]] {
        guard rolling, pendingCount > 0 else { return [] }
        return writeTail()
    }

    mutating func resetCounters() {
        cuts = 0
        skippedSamples = 0
    }

    /// Follows quiet quickly and loud slowly, so steady noise like a fan doesn't open the gate.
    private mutating func trackLoudness(_ rmsDb: Float) -> Bool {
        floorDb += (rmsDb - floorDb) * (rmsDb < floorDb ? 0.2 : 0.002)
        let loud = rmsDb > max(thresholdDb, floorDb + 10)
        loudBits = ((loudBits << 1) | (loud ? 1 : 0)) & 0xF
        return loud
    }

    private mutating func feedWhileRolling(_ chunk: [Int16], loud: Bool) -> [[Int16]] {
        if loud { return flushPending() + [chunk] }
        pending.append(chunk)
        pendingCount += chunk.count
        guard pendingCount > Self.maxPause else { return [] }
        let tail = writeTail()
        rolling = false
        loudBits = 0
        return tail
    }

    private mutating func feedWhileWaiting(_ chunk: [Int16], tapeHasAudio: Bool) -> [[Int16]] {
        ring.append(chunk)
        ringCount += chunk.count
        while ring.count > 1, ringCount - ring[0].count >= Self.preRoll {
            let dropped = ring.removeFirst()
            ringCount -= dropped.count
            skippedSamples += dropped.count
        }
        guard loudBits.nonzeroBitCount >= 2 else { return [] }
        if tapeHasAudio { cuts += 1 }
        rolling = true
        return flushRing(fadeIn: tapeHasAudio)
    }

    /// Keeps the first `tail` of the pause (faded out), remembers its last `preRoll`, drops the rest.
    private mutating func writeTail() -> [[Int16]] {
        let all = pending.flatMap { $0 }
        pending.removeAll()
        pendingCount = 0
        let keep = min(Self.tail, all.count)
        let restStart = max(keep, all.count - Self.preRoll)
        skippedSamples += restStart - keep
        if restStart < all.count {
            let remembered = Array(all[restStart...])
            ring.append(remembered)
            ringCount += remembered.count
        }
        return [Self.faded(Array(all[..<keep]), out: true)]
    }

    private mutating func flushPending() -> [[Int16]] {
        let chunks = pending
        pending.removeAll()
        pendingCount = 0
        return chunks
    }

    private mutating func flushRing(fadeIn: Bool) -> [[Int16]] {
        var chunks = ring
        ring.removeAll()
        ringCount = 0
        if fadeIn, let first = chunks.first {
            chunks[0] = Self.faded(first, out: false)
        }
        return chunks
    }

    static func faded(_ samples: [Int16], out: Bool) -> [Int16] {
        var result = samples
        let length = min(fadeLength, samples.count)
        for i in 0..<length {
            let gain = Float(i) / Float(length)
            let j = out ? samples.count - 1 - i : i
            result[j] = Int16(Float(samples[j]) * gain)
        }
        return result
    }
}
