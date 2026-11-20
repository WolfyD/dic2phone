import Foundation

/// The one sample format every tape is recorded in: 44.1 kHz mono 16-bit PCM, encoded to
/// AAC-LC at 96 kbps, the same as the Android app so tapes sound alike on both.
enum TapeFormat {
    static let sampleRate = 44_100
    static let chunkSize = 1024
    static let bitRate = 96_000
    static let label = "AAC-LC · 44.1 kHz · mono · 96 kbps"

    static func milliseconds(ofSamples samples: Int64) -> Int64 {
        samples * 1000 / Int64(sampleRate)
    }
}
