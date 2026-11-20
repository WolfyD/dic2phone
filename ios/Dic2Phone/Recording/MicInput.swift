import Foundation

/// The microphone, as a stream of tape-format chunks. The stream ends when the microphone
/// stops, whoever stopped it.
@MainActor
protocol MicInput: AnyObject {
    func start() throws -> AsyncStream<[Int16]>
    func stop()
}
