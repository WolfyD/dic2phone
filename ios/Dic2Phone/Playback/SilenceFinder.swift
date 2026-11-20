import Foundation

/// Finds the long silences on a tape from its sound as it's decoded: every 50 ms is measured,
/// and quiet stretches longer than a pause between words become gaps to skip.
struct SilenceFinder {
    private static let windowMs: Int64 = 50
    private static let windowLength = SpeechPieces.sampleRate / 20
    private static let shortestGapMs: Int64 = 1200
    private static let keptMs: Int64 = 300
    /// Quiet sits this far above the tape's own background level, kept between a hushed room
    /// and a loud one.
    private static let quietAboveFloorDb: Float = 9
    private static let quietThresholdRange: ClosedRange<Float> = -62 ... -32
    /// A blip this much louder than quiet, between two quiet windows, is a click or a cough of
    /// noise, and doesn't end a silence.
    private static let blipDb: Float = 6

    private var levels: [Float] = []
    private var energy: Double = 0
    private var counted = 0

    /// Decodes the whole tape: seconds of work for a long one, so it's done off the main actor.
    static func gaps(in source: TapeSource) async throws -> [SilenceGap] {
        let samples = try await source.samples()
        var finder = SilenceFinder()
        while let decoded = try samples.next() {
            try Task.checkCancellation()
            finder.append(decoded)
        }
        return finder.gaps()
    }

    mutating func append(_ samples: [Float]) {
        for sample in samples {
            energy += Double(sample * sample)
            counted += 1
            guard counted == Self.windowLength else { continue }
            levels.append(Float(10 * log10(energy / Double(counted) + 1e-10)))
            energy = 0
            counted = 0
        }
    }

    func gaps() -> [SilenceGap] {
        quietRuns().compactMap(Self.gap)
    }

    /// The stretches of quiet windows, by window index.
    private func quietRuns() -> [Range<Int>] {
        guard let threshold = quietThreshold else { return [] }
        var runs: [Range<Int>] = []
        var quietSince: Int?
        for index in levels.indices {
            if isQuiet(index, below: threshold) {
                quietSince = quietSince ?? index
            } else if let start = quietSince {
                runs.append(start ..< index)
                quietSince = nil
            }
        }
        if let start = quietSince {
            runs.append(start ..< levels.count)
        }
        return runs
    }

    /// Measured against this tape's own background, whatever the room was like.
    private var quietThreshold: Float? {
        guard !levels.isEmpty else { return nil }
        let floor = levels.sorted()[levels.count / 10]
        let range = Self.quietThresholdRange
        return min(max(floor + Self.quietAboveFloorDb, range.lowerBound), range.upperBound)
    }

    private func isQuiet(_ index: Int, below threshold: Float) -> Bool {
        if levels[index] < threshold { return true }
        guard levels[index] < threshold + Self.blipDb, index > 0, index < levels.count - 1 else { return false }
        return levels[index - 1] < threshold && levels[index + 1] < threshold
    }

    private static func gap(_ run: Range<Int>) -> SilenceGap? {
        let startMs = Int64(run.lowerBound) * windowMs
        let endMs = Int64(run.upperBound) * windowMs
        guard endMs - startMs >= shortestGapMs else { return nil }
        return SilenceGap(fromMs: startMs + keptMs, toMs: endMs - keptMs)
    }
}
