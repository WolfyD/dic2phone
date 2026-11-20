import Foundation

/// Where the samples of one tape go. The real one encodes to AAC; tests use a fake.
protocol TapeSink: AnyObject {
    func append(_ samples: [Int16], at sampleTime: Int64) async throws
    /// - Returns: true if a playable tape was written.
    func finish() async -> Bool
}
