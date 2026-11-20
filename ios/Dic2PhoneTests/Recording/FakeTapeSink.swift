@testable import Dic2Phone

/// Remembers what the engine writes instead of encoding it.
final class FakeTapeSink: TapeSink {
    private let failsOnAppend: Bool
    private(set) var sampleTimes: [Int64] = []
    private(set) var sampleCount = 0

    init(failsOnAppend: Bool) {
        self.failsOnAppend = failsOnAppend
    }

    func append(_ samples: [Int16], at sampleTime: Int64) async throws {
        if failsOnAppend { throw RecordingError.writerFailed }
        sampleTimes.append(sampleTime)
        sampleCount += samples.count
    }

    func finish() async -> Bool {
        sampleCount > 0
    }
}
