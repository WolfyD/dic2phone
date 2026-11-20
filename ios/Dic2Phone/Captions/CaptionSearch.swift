import Foundation

/// Finds words in the transcripts of many tapes, ignoring case and accents.
enum CaptionSearch {
    static let maxHits = 300

    static func hits(for query: String, in transcripts: [(tape: Tape, transcript: Transcript)]) -> [CaptionHit] {
        let wanted = folded(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !wanted.isEmpty else { return [] }
        var hits: [CaptionHit] = []
        for (tape, transcript) in transcripts {
            for cue in transcript.cues {
                guard let start = offset(of: wanted, in: folded(cue.text)) else { continue }
                hits.append(CaptionHit(tape: tape, cue: cue, characters: start..<start + wanted.count))
                if hits.count == maxHits { return hits }
            }
        }
        return hits
    }

    /// Lower case without accents, one character for each character of `text`, so a match's
    /// position is also its position in `text`.
    static func folded(_ text: String) -> [Character] {
        text.map { character in
            String(character).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).first ?? character
        }
    }

    private static func offset(of wanted: [Character], in text: [Character]) -> Int? {
        guard wanted.count <= text.count else { return nil }
        return (0...(text.count - wanted.count)).first { start in
            text[start..<start + wanted.count].elementsEqual(wanted)
        }
    }
}
