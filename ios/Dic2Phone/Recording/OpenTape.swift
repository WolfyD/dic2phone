import Foundation

/// The tape being written right now, with the running totals its metadata needs.
final class OpenTape {
    let id: TapeID
    let part: Int
    let startedAt: Date
    let sink: any TapeSink
    private(set) var samples: Int64 = 0
    private(set) var peak = 0
    private var sumOfSquares = 0.0

    init(id: TapeID, part: Int, startedAt: Date, sink: any TapeSink) {
        self.id = id
        self.part = part
        self.startedAt = startedAt
        self.sink = sink
    }

    var rmsDb: Float {
        samples > 0 ? ChunkLevel.decibels(meanSquare: sumOfSquares / Double(samples)) : -96
    }

    func append(_ chunk: [Int16]) async throws {
        try await sink.append(chunk, at: samples)
        for sample in chunk {
            let value = Int(sample)
            peak = max(peak, abs(value))
            sumOfSquares += Double(value) * Double(value)
        }
        samples += Int64(chunk.count)
    }
}
