import Foundation

/// The orders a tape list can be sorted in; tapping the sort key cycles through them.
enum TapeSort: String, CaseIterable, Sendable {
    case newest = "NEWEST"
    case oldest = "OLDEST"
    case longest = "LONGEST"
    case title = "TITLE"

    var label: String {
        switch self {
        case .newest: String(localized: "NEWEST")
        case .oldest: String(localized: "OLDEST")
        case .longest: String(localized: "LONGEST")
        case .title: String(localized: "A–Z")
        }
    }

    var next: TapeSort {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }

    func sorted(_ tapes: [Tape]) -> [Tape] {
        switch self {
        case .newest:
            tapes.sorted { $0.id > $1.id }
        case .oldest:
            tapes.sorted { $0.id < $1.id }
        case .longest:
            tapes.sorted { $0.durationMs > $1.durationMs }
        case .title:
            tapes.sorted(by: Self.titledFirst)
        }
    }

    /// Titled tapes first, A to Z ignoring case; untitled ones after them, newest first.
    private static func titledFirst(_ a: Tape, _ b: Tape) -> Bool {
        switch (a.title.isEmpty, b.title.isEmpty) {
        case (false, true): return true
        case (true, false): return false
        case (false, false):
            let order = a.title.localizedCaseInsensitiveCompare(b.title)
            return order == .orderedSame ? a.id > b.id : order == .orderedAscending
        case (true, true): return a.id > b.id
        }
    }
}
