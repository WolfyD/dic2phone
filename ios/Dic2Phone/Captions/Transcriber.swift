import Foundation

/// Listens to a whole tape with whisper.cpp, piece by piece, and puts its captions together.
struct Transcriber: Sendable {
    /// How often the progress of a piece being listened to is reported.
    private static let progressInterval = Duration.milliseconds(500)
    private static let stackSize = 8 * 1024 * 1024

    let model: WhisperModel
    /// A whisper language code, or "auto".
    let language: String

    /// - Parameter progress: percent of the tape done.
    func cues(
        of source: TapeSource,
        durationMs: Int64,
        progress: @escaping @Sendable (Int) async -> Void
    ) async throws -> [Cue] {
        let samples = try await source.samples()
        let totalSamples = max(1, durationMs * Int64(SpeechPieces.sampleRate) / 1000)
        var pieces = SpeechPieces()
        var cues: [Cue] = []
        while let decoded = try samples.next() {
            try Task.checkCancellation()
            for piece in pieces.append(decoded) {
                cues += try await listen(to: piece, of: totalSamples, progress: progress)
            }
        }
        if let last = pieces.finish() {
            cues += try await listen(to: last, of: totalSamples, progress: progress)
        }
        return cues
    }

    private func listen(
        to piece: SpeechPiece,
        of totalSamples: Int64,
        progress: @escaping @Sendable (Int) async -> Void
    ) async throws -> [Cue] {
        let reporter = Task {
            while !Task.isCancelled {
                let heard = piece.start + Int64(piece.samples.count) * Int64(model.progress) / 100
                await progress(min(99, Int(heard * 100 / totalSamples)))
                try? await Task.sleep(for: Self.progressInterval)
            }
        }
        defer { reporter.cancel() }
        let heard = try await transcribe(piece.samples)
        return heard.compactMap { Self.placed($0, at: piece.startMs) }
    }

    /// Runs whisper.cpp on a thread of its own: a piece takes minutes, far too long to hold
    /// one of Swift's few shared threads. The thread gets a main-thread-sized stack, as
    /// whisper.cpp is used to on other platforms, instead of the small default.
    private func transcribe(_ samples: [Float]) async throws -> [Cue] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let thread = Thread { [model, language] in
                    continuation.resume(with: Result { try model.transcribe(samples, language: language) })
                }
                thread.stackSize = Self.stackSize
                thread.qualityOfService = .userInitiated
                thread.start()
            }
        } onCancel: {
            model.cancel()
        }
    }

    /// A cue moved from its piece's time to the tape's, with characters whisper cut in half
    /// blanked; nil if nothing readable is left.
    private static func placed(_ cue: Cue, at offsetMs: Int64) -> Cue? {
        let text = cue.text.replacingOccurrences(of: "\u{FFFD}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return Cue(startMs: offsetMs + cue.startMs, endMs: offsetMs + cue.endMs, text: text)
    }
}
