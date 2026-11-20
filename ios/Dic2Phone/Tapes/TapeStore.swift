import AVFoundation

/// All file work on tapes and their metadata. An actor, so a tape is never moved and read,
/// or written twice, at the same time.
actor TapeStore {
    nonisolated let storage: Storage
    private var durationCache: [String: Int64] = [:]

    init(storage: Storage) {
        self.storage = storage
    }

    nonisolated func url(of tape: Tape) -> URL {
        storage.tapeURL(tape.id, in: tape.rack)
    }

    func tapes(in rack: Rack, heard: Set<TapeID>) async -> [Tape] {
        var tapes: [Tape] = []
        for id in storage.tapeIDs(in: storage.folder(for: rack)) {
            let url = storage.tapeURL(id, in: rack)
            let size = Self.fileSize(url)
            let meta = meta(for: id)
            let duration = meta.durationMs > 0 ? meta.durationMs : await measuredDuration(url, size: size)
            tapes.append(Tape(
                id: id,
                rack: rack,
                durationMs: duration,
                sizeBytes: size,
                isNew: rack == .deck && !heard.contains(id),
                title: meta.title,
                flags: meta.flags,
                hasCaptions: FileManager.default.fileExists(atPath: storage.captionsURL(id).path(percentEncoded: false))
            ))
        }
        return tapes
    }

    /// Never fails: a tape without readable metadata gets an empty record.
    func meta(for id: TapeID) -> TapeMeta {
        guard let data = try? Data(contentsOf: storage.metaURL(id)) else { return TapeMeta() }
        return (try? JSONDecoder().decode(TapeMeta.self, from: data)) ?? TapeMeta()
    }

    func saveMeta(_ meta: TapeMeta, for id: TapeID) throws {
        let data = try JSONEncoder().encode(meta)
        try data.write(to: storage.metaURL(id), options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    func updateMeta(of id: TapeID, _ change: @Sendable (inout TapeMeta) -> Void) throws {
        var updated = meta(for: id)
        change(&updated)
        try saveMeta(updated, for: id)
    }

    /// Nil if the tape has no captions yet.
    func transcript(of id: TapeID) -> Transcript? {
        guard let text = try? String(contentsOf: storage.captionsURL(id), encoding: .utf8) else { return nil }
        return Transcript(cues: SubRip.cues(in: text))
    }

    func saveTranscript(_ transcript: Transcript, for id: TapeID) throws {
        let text = SubRip.text(of: transcript.cues)
        try Data(text.utf8).write(to: storage.captionsURL(id), options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    /// Moves a finished recording onto the deck and writes down what is known about it.
    func keepRecording(_ id: TapeID, meta: TapeMeta) throws {
        let destination = storage.tapeURL(id, in: .deck)
        try FileManager.default.moveItem(at: storage.recordingURL(id), to: destination)
        try? FileManager.default.removeItem(at: storage.rescueNoteURL(id))
        var described = meta
        described.sizeBytes = Self.fileSize(destination)
        try saveMeta(described, for: id)
    }

    func discardRecording(_ id: TapeID) {
        try? FileManager.default.removeItem(at: storage.recordingURL(id))
        try? FileManager.default.removeItem(at: storage.rescueNoteURL(id))
    }

    /// - Returns: how many tapes couldn't be deleted.
    func delete(_ tapes: [Tape]) -> Int {
        var failures = 0
        for tape in tapes {
            do {
                try FileManager.default.removeItem(at: url(of: tape))
                try? FileManager.default.removeItem(at: storage.metaURL(tape.id))
                try? FileManager.default.removeItem(at: storage.captionsURL(tape.id))
            } catch {
                failures += 1
            }
        }
        return failures
    }

    /// - Returns: how many tapes were moved from the deck to the shelf.
    func shelve(_ tapes: [Tape]) -> Int {
        var moved = 0
        for tape in tapes where tape.rack == .deck {
            let destination = storage.tapeURL(tape.id, in: .shelf)
            guard (try? FileManager.default.moveItem(at: url(of: tape), to: destination)) != nil else { continue }
            moved += 1
        }
        return moved
    }

    private func measuredDuration(_ url: URL, size: Int64) async -> Int64 {
        let key = "\(url.lastPathComponent):\(size)"
        if let cached = durationCache[key] { return cached }
        guard let duration = try? await AVURLAsset(url: url).load(.duration), duration.isNumeric else { return 0 }
        let ms = Int64(duration.seconds * 1000)
        durationCache[key] = ms
        return ms
    }

    private static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
