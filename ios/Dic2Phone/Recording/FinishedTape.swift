import Foundation

/// A tape the engine has closed, with everything the recorder writes into its metadata.
struct FinishedTape: Sendable {
    let id: TapeID
    let written: Bool
    let part: Int
    let samples: Int64
    let peak: Int
    let rmsDb: Float
    let flags: [Int64]
    let vox: Bool
    let cuts: Int
    let skippedMs: Int64
    let startedAt: Date
    let endedAt: Date

    var durationMs: Int64 { TapeFormat.milliseconds(ofSamples: samples) }
    var peakDb: Float { ChunkLevel.peakDecibels(peak) }
}
