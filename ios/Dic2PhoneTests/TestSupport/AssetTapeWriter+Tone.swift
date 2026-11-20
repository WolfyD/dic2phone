import Foundation
@testable import Dic2Phone

extension AssetTapeWriter {
    /// A tape of a steady tone, recorded the way the app records.
    static func recordTone(to url: URL, seconds: Int) async throws {
        let writer = try AssetTapeWriter(url: url)
        let chunk = (0..<TapeFormat.chunkSize).map { Int16(8_000 * sin(Double($0) * 0.1)) }
        let chunkCount = TapeFormat.sampleRate * seconds / TapeFormat.chunkSize
        for index in 0..<chunkCount {
            try await writer.append(chunk, at: Int64(index * TapeFormat.chunkSize))
        }
        _ = await writer.finish()
    }
}
