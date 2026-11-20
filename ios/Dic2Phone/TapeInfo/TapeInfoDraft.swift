import Foundation

/// What's written about a tape in TAPE INFO, as typed, before it's tidied and saved.
struct TapeInfoDraft: Equatable, Sendable {
    static let tagsInputLimit = 300
    static let flagNoteLimit = 120

    var title: String
    var notes: String
    /// Comma separated, as typed.
    var tags: String
    var flagNotes: [Int64: String]

    init(meta: TapeMeta) {
        title = meta.title
        notes = meta.notes
        tags = meta.tags.joined(separator: ", ")
        flagNotes = meta.flagNotes
    }

    /// Tags split on commas and #, each kept once whatever its case.
    var tagList: [String] {
        var seen = Set<String>()
        let tags = tags
            .split(whereSeparator: { $0 == "," || $0 == "#" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        return Array(tags.prefix(TapeMeta.tagsLimit))
    }

    func apply(to meta: inout TapeMeta) {
        meta.title = Self.tidy(title, limit: TapeMeta.titleLimit)
        meta.notes = Self.tidy(notes, limit: TapeMeta.notesLimit)
        meta.tags = tagList
        meta.flagNotes = flagNotes
            .mapValues { Self.tidy($0, limit: Self.flagNoteLimit) }
            .filter { !$0.value.isEmpty }
    }

    private static func tidy(_ text: String, limit: Int) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }
}
