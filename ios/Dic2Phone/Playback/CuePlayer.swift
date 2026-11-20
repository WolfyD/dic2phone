import AVFoundation

/// TAPE WIND's CUE: the tape heard as it winds, four times as fast and an octave up, as a real
/// deck sounds with its heads against the tape. Rewinding, it plays backwards: each second of
/// tape is read and turned round.
@MainActor
final class CuePlayer {
    private static let speed: Float = 4
    private static let pitchCents: Float = 1200
    /// Read this far ahead of what's heard, so the sound never runs dry.
    private static let readAheadMs: Int64 = 2000
    private static let tick: Duration = .milliseconds(30)

    private let audioSession: AudioSession

    init(audioSession: AudioSession) {
        self.audioSession = audioSession
    }

    /// Plays from `fromMs` until cancelled or the tape runs out, telling `moved` where the tape
    /// has got to.
    /// - Returns: whether the tape ran out.
    func play(
        _ source: TapeSource,
        fromMs: Int64,
        durationMs: Int64,
        forward: Bool,
        moved: (Int64) -> Void
    ) async -> Bool {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(SpeechPieces.sampleRate), channels: 1),
              (try? audioSession.activate()) != nil else { return false }
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.rate = Self.speed
        timePitch.pitch = Self.pitchCents
        engine.attach(node)
        engine.attach(timePitch)
        engine.connect(node, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        guard (try? engine.start()) != nil else { return false }
        defer {
            node.stop()
            engine.stop()
        }
        node.play()

        var pieces = CuePieces(fromMs: fromMs, durationMs: durationMs, forward: forward)
        var queuedMs: Int64 = 0
        while (try? await Task.sleep(for: Self.tick)) != nil {
            let heardMs = min(Self.heardMs(by: node), queuedMs)
            moved(pieces.position(afterHearing: heardMs))
            if pieces.isAllRead, heardMs >= queuedMs { return true }
            guard queuedMs - heardMs < Self.readAheadMs, let piece = pieces.next() else { continue }
            let samples = (try? await source.decoded(piece)) ?? []
            guard !Task.isCancelled else { return false }
            guard let buffer = PCMBuffers.buffer(forward ? samples : Array(samples.reversed()), format: format) else { continue }
            node.scheduleBuffer(buffer, completionHandler: nil)
            queuedMs += Int64(buffer.frameLength) * 1000 / Int64(SpeechPieces.sampleRate)
        }
        return false
    }

    /// The player node counts the tape's samples as the time-pitch unit takes them, so this
    /// runs four times faster than the clock.
    private static func heardMs(by node: AVAudioPlayerNode) -> Int64 {
        guard let renderTime = node.lastRenderTime, let time = node.playerTime(forNodeTime: renderTime) else { return 0 }
        return max(time.sampleTime, 0) * 1000 / Int64(time.sampleRate)
    }
}
