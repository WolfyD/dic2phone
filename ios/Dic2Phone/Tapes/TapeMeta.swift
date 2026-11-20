import Foundation

/// Everything known about one tape: facts the recorder wrote down, what the user wrote on the
/// label, and the flagged moments. Stored as JSON with the same keys as the Android app.
struct TapeMeta: Equatable, Sendable {
    static let tagsLimit = 12
    static let titleLimit = 60
    static let notesLimit = 4000

    var title = ""
    var notes = ""
    var tags: [String] = []
    var startedAtMs: Int64 = 0
    var endedAtMs: Int64 = 0
    var durationMs: Int64 = 0
    var sizeBytes: Int64 = 0
    var format = ""
    var peakDb: Double?
    var averageDb: Double?
    /// What started the recording: rec-key, widget, recovered, ...
    var source = ""
    var device = ""
    var latched = false
    var vox = false
    var cuts = 0
    var skippedMs: Int64 = 0
    /// 1, 2, ... when a long session was split into hour tapes; 0 otherwise.
    var part = 0
    /// Milliseconds from the start of the tape, sorted.
    var flags: [Int64] = []
    var flagNotes: [Int64: String] = [:]
}

extension TapeMeta: Codable {
    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case title, notes, tags
        case startedAtMs = "start"
        case endedAtMs = "end"
        case durationMs = "dur"
        case sizeBytes = "size"
        case format
        case peakDb = "peak"
        case averageDb = "avg"
        case source, device, latched, vox, cuts
        case skippedMs = "skipped"
        case part, flags, flagNotes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        startedAtMs = try c.decodeIfPresent(Int64.self, forKey: .startedAtMs) ?? 0
        endedAtMs = try c.decodeIfPresent(Int64.self, forKey: .endedAtMs) ?? 0
        durationMs = try c.decodeIfPresent(Int64.self, forKey: .durationMs) ?? 0
        sizeBytes = try c.decodeIfPresent(Int64.self, forKey: .sizeBytes) ?? 0
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? ""
        peakDb = try c.decodeIfPresent(Double.self, forKey: .peakDb)
        averageDb = try c.decodeIfPresent(Double.self, forKey: .averageDb)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        device = try c.decodeIfPresent(String.self, forKey: .device) ?? ""
        latched = try c.decodeIfPresent(Bool.self, forKey: .latched) ?? false
        vox = try c.decodeIfPresent(Bool.self, forKey: .vox) ?? false
        cuts = try c.decodeIfPresent(Int.self, forKey: .cuts) ?? 0
        skippedMs = try c.decodeIfPresent(Int64.self, forKey: .skippedMs) ?? 0
        part = try c.decodeIfPresent(Int.self, forKey: .part) ?? 0
        flags = (try c.decodeIfPresent([Int64].self, forKey: .flags) ?? []).sorted()
        let notesByKey = try c.decodeIfPresent([String: String].self, forKey: .flagNotes) ?? [:]
        let parsedNotes = notesByKey.compactMap { key, note in Int64(key).map { ($0, note) } }
        flagNotes = Dictionary(parsedNotes, uniquingKeysWith: { first, _ in first })
    }

    /// Empty and default values are left out, like the Android app does.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(1, forKey: .version)
        try c.encodeUnlessEmpty(title, forKey: .title)
        try c.encodeUnlessEmpty(notes, forKey: .notes)
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
        try c.encodeUnlessZero(startedAtMs, forKey: .startedAtMs)
        try c.encodeUnlessZero(endedAtMs, forKey: .endedAtMs)
        try c.encodeUnlessZero(durationMs, forKey: .durationMs)
        try c.encodeUnlessZero(sizeBytes, forKey: .sizeBytes)
        try c.encodeUnlessEmpty(format, forKey: .format)
        try c.encodeIfPresent(peakDb, forKey: .peakDb)
        try c.encodeIfPresent(averageDb, forKey: .averageDb)
        try c.encodeUnlessEmpty(source, forKey: .source)
        try c.encodeUnlessEmpty(device, forKey: .device)
        if latched { try c.encode(true, forKey: .latched) }
        if vox { try c.encode(true, forKey: .vox) }
        try c.encodeUnlessZero(Int64(cuts), forKey: .cuts)
        try c.encodeUnlessZero(skippedMs, forKey: .skippedMs)
        try c.encodeUnlessZero(Int64(part), forKey: .part)
        if !flags.isEmpty { try c.encode(flags, forKey: .flags) }
        // Notes only for flags that still exist: removing a flag drops its note too.
        let liveNotes = flagNotes.filter { flags.contains($0.key) && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        if !liveNotes.isEmpty {
            let notesByKey = Dictionary(uniqueKeysWithValues: liveNotes.map { (String($0.key), $0.value) })
            try c.encode(notesByKey, forKey: .flagNotes)
        }
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeUnlessEmpty(_ value: String, forKey key: Key) throws {
        if !value.isEmpty { try encode(value, forKey: key) }
    }

    mutating func encodeUnlessZero(_ value: Int64, forKey key: Key) throws {
        if value != 0 { try encode(value, forKey: key) }
    }
}
