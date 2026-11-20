import Foundation

/// The .srt subtitle format captions are kept in, so they can be sent to any video player.
enum SubRip {
    static func text(of cues: [Cue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(timestamp(cue.startMs)) --> \(timestamp(cue.endMs))\n\(cue.text)\n\n"
        }.joined()
    }

    /// The cues in `text`; anything that isn't a cue is skipped.
    static func cues(in text: String) -> [Cue] {
        let timing = #/(\d{1,4}):(\d\d):(\d\d)[,.](\d{1,3})\s*-->\s*(\d{1,4}):(\d\d):(\d\d)[,.](\d{1,3})/#
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)[...]
        var cues: [Cue] = []
        while let line = lines.popFirst() {
            guard let match = line.firstMatch(of: timing)?.output,
                  let startMs = milliseconds(match.1, match.2, match.3, match.4),
                  let endMs = milliseconds(match.5, match.6, match.7, match.8) else { continue }
            let textLines = lines.prefix { !$0.allSatisfy(\.isWhitespace) }
            lines = lines.dropFirst(textLines.count)
            let text = textLines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
            cues.append(Cue(startMs: startMs, endMs: endMs, text: text))
        }
        return cues
    }

    private static func timestamp(_ ms: Int64) -> String {
        String(format: "%02lld:%02lld:%02lld,%03lld", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }

    /// "5" after the comma means 500 ms, as in a decimal fraction.
    private static func milliseconds(_ hours: Substring, _ minutes: Substring, _ seconds: Substring, _ fraction: Substring) -> Int64? {
        let thousandths = fraction + String(repeating: "0", count: max(3 - fraction.count, 0))
        guard let hours = Int64(hours), let minutes = Int64(minutes), let seconds = Int64(seconds),
              let thousandths = Int64(thousandths) else { return nil }
        return ((hours * 60 + minutes) * 60 + seconds) * 1000 + thousandths
    }
}
