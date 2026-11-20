import Foundation

/// What's on the cassette's label: a big line, a small line under it, and whether the big line
/// is the user's own writing (drawn in their pen) or printed.
struct CassetteLabel: Equatable {
    private static var stock: String { String(localized: "C-60 · TYPE I · NORMAL") }

    var title: String
    var subtitle: String
    var handwritten: Bool

    /// A tape in the deck: its title or recording date. A titled tape keeps its date underneath;
    /// an untitled one shows where it's at instead.
    static func inDeck(_ tape: Tape, positionMs: Int64, playing: Bool) -> CassetteLabel {
        let titled = !tape.title.isEmpty
        let whereAt = "\(playing ? Glyph.play : Glyph.pause) \(TapeNames.duration(ms: positionMs)) / \(TapeNames.duration(ms: tape.durationMs))"
        return CassetteLabel(
            title: TapeNames.label(tape),
            subtitle: titled ? TapeNames.pretty(tape.id) : whereAt,
            handwritten: titled
        )
    }

    /// A tape playing from a list.
    static func playing(_ tape: Tape, positionMs: Int64) -> CassetteLabel {
        let at = "\(TapeNames.duration(ms: positionMs)) / \(TapeNames.duration(ms: tape.durationMs))"
        return CassetteLabel(
            title: TapeNames.label(tape),
            subtitle: String(localized: "PLAYING · \(at)"),
            handwritten: !tape.title.isEmpty
        )
    }

    /// Setup's example of how the user's writing looks.
    static func sample(userLabel: String) -> CassetteLabel {
        CassetteLabel(
            title: userLabel.isEmpty ? String(localized: "My first tape") : userLabel,
            subtitle: stock,
            handwritten: true
        )
    }

    /// The deck's own label with no tape in: the user's writing, if any, stays on the big line;
    /// the rest tells what the deck is doing or what the last tape was.
    static func empty(userLabel: String, recording: Bool, last: Tape?) -> CassetteLabel {
        let written = !userLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if written {
            return CassetteLabel(title: userLabel, subtitle: activity(recording: recording, last: last), handwritten: true)
        }
        if recording {
            return CassetteLabel(title: String(localized: "RECORDING…"), subtitle: stock, handwritten: false)
        }
        guard let last else {
            return CassetteLabel(title: "", subtitle: stock, handwritten: false)
        }
        return CassetteLabel(
            title: TapeNames.pretty(last.id),
            subtitle: String(localized: "LAST TAPE · \(summary(of: last))"),
            handwritten: false
        )
    }

    private static func activity(recording: Bool, last: Tape?) -> String {
        if recording { return String(localized: "\(Glyph.rec) RECORDING…") }
        guard let last else { return stock }
        return String(localized: "LAST \(TapeNames.pretty(last.id)) · \(summary(of: last))")
    }

    /// "4:05", or "4:05 · NEW" if it hasn't been heard yet.
    private static func summary(of tape: Tape) -> String {
        let duration = TapeNames.duration(ms: tape.durationMs)
        return tape.isNew ? "\(duration) · \(String(localized: "NEW"))" : duration
    }
}
