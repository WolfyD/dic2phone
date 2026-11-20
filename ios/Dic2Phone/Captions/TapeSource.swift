import AVFoundation

/// Where a tape's sound is decoded from: its plain file, or its sealed one in the vault,
/// decrypted only in memory.
enum TapeSource: Sendable {
    case plain(URL)
    case sealed(SealedFile)

    /// - Parameter timeRange: only this stretch of the tape; nil for all of it.
    func samples(during timeRange: CMTimeRange? = nil) async throws -> TapeSamples {
        switch self {
        case .plain(let url):
            return try await TapeSamples(asset: AVURLAsset(url: url), timeRange: timeRange)
        case .sealed(let file):
            let loader = SealedAssetLoader(file: file)
            guard let asset = loader.makeAsset() else { throw CaptionError.tapeUnreadable }
            return try await TapeSamples(asset: asset, loader: loader, timeRange: timeRange)
        }
    }

    /// All the samples in a short stretch of the tape, given in milliseconds.
    func decoded(_ stretchMs: Range<Int64>) async throws -> [Float] {
        let timeRange = CMTimeRange(
            start: CMTime(value: stretchMs.lowerBound, timescale: 1000),
            end: CMTime(value: stretchMs.upperBound, timescale: 1000)
        )
        let samples = try await samples(during: timeRange)
        var decoded: [Float] = []
        while let more = try samples.next() {
            decoded += more
        }
        return decoded
    }
}
