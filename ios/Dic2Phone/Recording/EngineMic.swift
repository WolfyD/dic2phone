import AVFoundation

/// The real microphone, through AVAudioEngine's input node.
@MainActor
final class EngineMic: MicInput {
    private static let tapBufferFrames: AVAudioFrameCount = 4096

    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<[Int16]>.Continuation?
    private var routeWatch: Task<Void, Never>?

    func start() throws -> AsyncStream<[Int16]> {
        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw RecordingError.micUnavailable
        }
        let chunker = try MicChunker(from: hardwareFormat)
        let (stream, continuation) = AsyncStream<[Int16]>.makeStream()
        input.installTap(
            onBus: 0,
            bufferSize: Self.tapBufferFrames,
            format: hardwareFormat,
            block: Self.tapBlock(chunker: chunker, continuation: continuation)
        )
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw RecordingError.micUnavailable
        }
        self.continuation = continuation
        watchForRouteChanges()
        return stream
    }

    func stop() {
        routeWatch?.cancel()
        routeWatch = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
    }

    /// Built outside the main actor: the tap runs on Core Audio's own thread.
    private nonisolated static func tapBlock(
        chunker: MicChunker,
        continuation: AsyncStream<[Int16]>.Continuation
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            for chunk in chunker.chunks(from: buffer) {
                continuation.yield(chunk)
            }
        }
    }

    /// A headset plugged in or out reconfigures the engine and silently stops the input; end the
    /// stream so the recorder closes the tape instead of waiting forever.
    private func watchForRouteChanges() {
        let changes = NotificationCenter.default.notifications(named: .AVAudioEngineConfigurationChange, object: engine)
        routeWatch = Task { [weak self] in
            for await _ in changes {
                self?.stop()
                return
            }
        }
    }
}
