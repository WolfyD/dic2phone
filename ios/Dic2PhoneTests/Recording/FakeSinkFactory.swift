import Foundation
@testable import Dic2Phone

/// Hands the engine fake sinks and keeps them for the test to look at. The engine calls it from
/// its own actor while the test reads between awaits, hence the lock.
final class FakeSinkFactory: @unchecked Sendable {
    private let refusesToOpen: Bool
    private let failsOnAppend: Bool
    private let lock = NSLock()
    private var made: [FakeTapeSink] = []

    init(refusesToOpen: Bool = false, failsOnAppend: Bool = false) {
        self.refusesToOpen = refusesToOpen
        self.failsOnAppend = failsOnAppend
    }

    var sinks: [FakeTapeSink] {
        lock.withLock { made }
    }

    func makeSink(at url: URL) throws -> any TapeSink {
        if refusesToOpen { throw RecordingError.writerFailed }
        // The real writer creates its file at once, so the next tape in the same second needs a new name.
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        let sink = FakeTapeSink(failsOnAppend: failsOnAppend)
        lock.withLock { made.append(sink) }
        return sink
    }
}
