import Foundation

/// A tape's captions, in order. Empty when no speech was found on the tape.
struct Transcript: Equatable, Sendable {
    /// A caption stays up this long after it ends, so short pauses don't make it flicker.
    static let lingerMs: Int64 = 1500
    /// A pause this long starts a new paragraph in the readable text.
    private static let paragraphPauseMs: Int64 = 2500

    let cues: [Cue]

    /// The cue being spoken at `ms`, if any.
    func index(atMs ms: Int64) -> Int? {
        let started = countStarted(byMs: ms)
        guard started > 0, ms <= cues[started - 1].endMs + Self.lingerMs else { return nil }
        return started - 1
    }

    /// How many cues start at or before `ms`, found by binary search.
    private func countStarted(byMs ms: Int64) -> Int {
        var low = 0
        var high = cues.count
        while low < high {
            let middle = (low + high) / 2
            if cues[middle].startMs <= ms {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    func cue(atMs ms: Int64) -> Cue? {
        index(atMs: ms).map { cues[$0] }
    }

    /// Plain text to read or send: paragraphs broken at pauses, each with the time it starts.
    func readable(heading: String) -> String {
        var paragraphs: [String] = []
        var lastEndMs: Int64?
        for cue in cues {
            let text = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let lastEndMs, cue.startMs - lastEndMs <= Self.paragraphPauseMs, let paragraph = paragraphs.popLast() {
                paragraphs.append(paragraph + " " + text)
            } else {
                paragraphs.append("[\(TapeNames.duration(ms: cue.startMs))] " + text)
            }
            lastEndMs = cue.endMs
        }
        return ([heading] + paragraphs).joined(separator: "\n\n") + "\n"
    }
}
