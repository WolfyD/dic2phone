/// Where CUE reads the tape: a second at a time from where the deck is, onwards or back.
struct CuePieces {
    private static let pieceMs: Int64 = 1000

    private let fromMs: Int64
    private let durationMs: Int64
    private let forward: Bool
    private var nextMs: Int64

    init(fromMs: Int64, durationMs: Int64, forward: Bool) {
        self.durationMs = max(durationMs, 0)
        self.fromMs = min(max(fromMs, 0), self.durationMs)
        self.forward = forward
        nextMs = self.fromMs
    }

    /// The next stretch to read, in tape time; nil once the tape has run out.
    mutating func next() -> Range<Int64>? {
        if forward {
            guard nextMs < durationMs else { return nil }
            let piece = nextMs ..< min(nextMs + Self.pieceMs, durationMs)
            nextMs = piece.upperBound
            return piece
        }
        guard nextMs > 0 else { return nil }
        let piece = max(nextMs - Self.pieceMs, 0) ..< nextMs
        nextMs = piece.lowerBound
        return piece
    }

    var isAllRead: Bool {
        forward ? nextMs >= durationMs : nextMs <= 0
    }

    /// Where the tape is once `heardMs` of it has been heard.
    func position(afterHearing heardMs: Int64) -> Int64 {
        forward ? min(fromMs + heardMs, durationMs) : max(fromMs - heardMs, 0)
    }
}
