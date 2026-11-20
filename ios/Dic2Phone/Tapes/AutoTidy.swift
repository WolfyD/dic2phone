import Foundation

/// AUTO-TIDY: heard deck tapes are deleted this many days after they were recorded. Unheard
/// tapes, tapes with a title or flags, and the tape in the deck are kept, as is everything on the
/// shelf or in the vault. Tapes due within `warningDays` are marked, so there's time to keep them.
struct AutoTidy {
    static let choices = [0, 7, 14, 30, 90]
    static let warningDays = 3
    private static let day: TimeInterval = 86_400

    /// 0 is off.
    let days: Int
    /// The tapes in the deck or playing.
    let kept: Set<TapeID>

    /// When each deck tape that will be tidied goes.
    func due(in deck: [Tape]) -> [TapeID: Date] {
        guard days > 0 else { return [:] }
        let lifetime = Double(days) * Self.day
        let due = deck.compactMap { tape -> (TapeID, Date)? in
            guard isTidyable(tape), let recordedAt = tape.recordedAt else { return nil }
            let endedAt = recordedAt.addingTimeInterval(Double(tape.durationMs) / 1000)
            return (tape.id, endedAt.addingTimeInterval(lifetime))
        }
        return Dictionary(due, uniquingKeysWith: { first, _ in first })
    }

    /// Those due within the warning window, or overdue.
    func dueSoon(in deck: [Tape], now: Date) -> [TapeID: Date] {
        let warningEnds = now.addingTimeInterval(Double(Self.warningDays) * Self.day)
        return due(in: deck).filter { $0.value <= warningEnds }
    }

    func overdue(in deck: [Tape], now: Date) -> [Tape] {
        let due = due(in: deck)
        return deck.filter { tape in due[tape.id].map { $0 <= now } ?? false }
    }

    /// "TOMORROW", "IN 2 DAYS".
    static func whenText(of date: Date, now: Date) -> String {
        let left = date.timeIntervalSince(now)
        let days = Int(left / day)
        if left <= 0 { return String(localized: "SOON") }
        switch days {
        case 0: return String(localized: "TODAY")
        case 1: return String(localized: "TOMORROW")
        default: return String(localized: "IN \(days) DAYS")
        }
    }

    private func isTidyable(_ tape: Tape) -> Bool {
        tape.rack == .deck && !tape.isNew && tape.title.isEmpty && tape.flags.isEmpty && !kept.contains(tape.id)
    }
}

extension AutoTidy {
    /// As set up now, keeping the tapes in the deck and playing.
    @MainActor
    init(settings: Settings, player: Player) {
        let kept = [settings.deckTape, player.loadedID, player.playingID].compactMap { $0 }
        self.init(days: settings.tidyDays, kept: Set(kept))
    }
}
