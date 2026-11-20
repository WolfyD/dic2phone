import Foundation

/// Makes one effect copy: decodes a plain tape, runs it through a `TapeProcessor`, and encodes
/// the result the same way tapes are recorded.
enum EffectRenderer {
    /// - Returns: whether the copy was finished; false if the tape couldn't be read or
    ///   written, or the work was cancelled.
    static func render(_ tape: URL, to copy: URL, with effects: TapeEffects) async -> Bool {
        guard let samples = try? await TapeSource.plain(tape).samples(sampleRate: TapeFormat.sampleRate),
              let writer = try? AssetTapeWriter(url: copy) else { return false }
        var processor = TapeProcessor(effects: effects, sampleRate: Double(TapeFormat.sampleRate))
        var written: Int64 = 0
        do {
            while var chunk = try samples.next() {
                try Task.checkCancellation()
                guard !chunk.isEmpty else { continue }
                processor.process(&chunk)
                try await writer.append(chunk.map(Self.int16), at: written)
                written += Int64(chunk.count)
            }
        } catch {
            _ = await writer.finish()
            return false
        }
        let finished = await writer.finish()
        return finished && written > 0
    }

    /// Clamped, so a peak lifted past full scale clips instead of wrapping around.
    private static func int16(_ sample: Float) -> Int16 {
        guard sample.isFinite else { return 0 }
        return Int16(min(max(sample, -1), 1) * Float(Int16.max))
    }
}
