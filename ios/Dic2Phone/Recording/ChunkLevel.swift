import Foundation

/// How loud one chunk of samples is: its peak and its RMS in dBFS.
struct ChunkLevel {
    let peak: Int
    let rmsDb: Float

    init(_ chunk: [Int16]) {
        var peak = 0
        var sumOfSquares = 0.0
        for sample in chunk {
            let magnitude = abs(Int(sample))
            peak = max(peak, magnitude)
            sumOfSquares += Double(magnitude) * Double(magnitude)
        }
        self.peak = peak
        self.rmsDb = Self.decibels(meanSquare: sumOfSquares / Double(max(chunk.count, 1)))
    }

    static func decibels(meanSquare: Double) -> Float {
        Float(10 * log10(max(meanSquare, 1) / (32768.0 * 32768.0)))
    }

    static func peakDecibels(_ peak: Int) -> Float {
        20 * log10(Float(max(peak, 1)) / 32767)
    }
}
