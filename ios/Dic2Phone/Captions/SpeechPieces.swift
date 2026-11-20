/// Cuts a tape's samples into pieces of about five minutes, so a long tape never has to be in
/// memory whole. Each cut is made at the quietest moment near the end of a piece, so no word is
/// split in two.
struct SpeechPieces {
    static let sampleRate = 16_000
    private static let pieceLength = sampleRate * 300
    private static let searchLength = sampleRate * 30
    private static let windowLength = sampleRate / 10
    /// Whisper makes up words when it hears near silence, so pieces this quiet are skipped.
    private static let silenceLevel: Float = 0.002
    /// Less than this at the end of a tape is too short to hold a word.
    private static let shortestEnding = sampleRate / 4

    private var pending: [Float] = []
    private var pendingStart: Int64 = 0

    /// - Returns: the pieces that are complete now, silent ones left out.
    mutating func append(_ samples: [Float]) -> [SpeechPiece] {
        pending += samples
        var pieces: [SpeechPiece] = []
        while pending.count >= Self.pieceLength + Self.searchLength {
            let cut = Self.quietestMoment(in: pending, from: Self.pieceLength, to: Self.pieceLength + Self.searchLength)
            if let piece = take(cut) { pieces.append(piece) }
        }
        return pieces
    }

    /// - Returns: what is left at the end of the tape, unless it is silent or too short.
    mutating func finish() -> SpeechPiece? {
        guard pending.count > Self.shortestEnding else { return nil }
        return take(pending.count)
    }

    /// - Returns: the first `count` pending samples as a piece, unless they are silent.
    private mutating func take(_ count: Int) -> SpeechPiece? {
        let piece = SpeechPiece(start: pendingStart, samples: Array(pending.prefix(count)))
        pending.removeFirst(count)
        pendingStart += Int64(count)
        return Self.loudness(of: piece.samples[...]) > Self.silenceLevel ? piece : nil
    }

    /// The middle of the quietest tenth of a second between `start` and `end`, looking at
    /// windows that overlap by half.
    private static func quietestMoment(in samples: [Float], from start: Int, to end: Int) -> Int {
        var quietest = start
        var quietestLoudness = Float.greatestFiniteMagnitude
        for windowStart in stride(from: start, through: end - windowLength, by: windowLength / 2) {
            let loudness = loudness(of: samples[windowStart..<windowStart + windowLength])
            if loudness < quietestLoudness {
                quietestLoudness = loudness
                quietest = windowStart + windowLength / 2
            }
        }
        return quietest
    }

    /// Root mean square.
    private static func loudness(of samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(Double(0)) { $0 + Double($1 * $1) }
        return Float((sumOfSquares / Double(samples.count)).squareRoot())
    }
}
