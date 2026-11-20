/// A stretch of a tape for whisper.cpp to listen to.
struct SpeechPiece: Sendable {
    /// Where it starts on the tape, counted in samples.
    let start: Int64
    let samples: [Float]

    var startMs: Int64 {
        start * 1000 / Int64(SpeechPieces.sampleRate)
    }
}
