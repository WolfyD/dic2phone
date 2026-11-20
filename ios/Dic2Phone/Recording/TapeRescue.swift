import AVFoundation

/// Saves tapes cut off by a crash, a kill or a flat battery. The writer flushes the file in
/// fragments as it goes, so what was recorded up to the last fragment is still readable; this
/// copies it onto the deck as a proper file with its metadata.
struct TapeRescue {
    private static let minTapeMs: Int64 = 700

    let store: TapeStore
    let device: String

    /// The tapes left behind by an earlier run. Taken at launch, before anything can record, so
    /// a tape that starts meanwhile is never mistaken for a cut-off one.
    func leftovers() -> [TapeID] {
        store.storage.tapeIDs(in: store.storage.recording)
    }

    /// - Returns: how many tapes were saved.
    func rescue(_ leftovers: [TapeID]) async -> Int {
        var rescued = 0
        for id in leftovers {
            if await rescue(id) { rescued += 1 }
        }
        return rescued
    }

    private func rescue(_ id: TapeID) async -> Bool {
        let storage = store.storage
        let source = storage.recordingURL(id)
        let asset = AVURLAsset(url: source)
        guard let durationMs = await Self.durationMs(of: asset), durationMs >= Self.minTapeMs else {
            await store.discardRecording(id)
            return false
        }
        let destination = storage.tapeURL(id, in: .deck)
        // A failed copy keeps the original for another try next launch: it's the only copy.
        guard await Self.copy(asset, to: destination) else { return false }
        let endedAt = (try? source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
        let note = RescueNote.read(from: storage.rescueNoteURL(id))
        try? await store.saveMeta(meta(durationMs: durationMs, endedAt: endedAt, note: note, tapeFile: destination), for: id)
        await store.discardRecording(id)
        return true
    }

    private func meta(durationMs: Int64, endedAt: Date, note: RescueNote?, tapeFile: URL) -> TapeMeta {
        let endedAtMs = Int64(endedAt.timeIntervalSince1970 * 1000)
        var meta = TapeMeta()
        meta.startedAtMs = note?.startedAtMs ?? endedAtMs - durationMs
        meta.endedAtMs = endedAtMs
        meta.durationMs = durationMs
        meta.sizeBytes = Int64((try? tapeFile.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        meta.format = TapeFormat.label
        meta.source = "recovered"
        meta.device = device
        meta.vox = note?.vox ?? false
        meta.flags = (note?.flags ?? []).filter { $0 < durationMs }
        return meta
    }

    private static func durationMs(of asset: AVURLAsset) async -> Int64? {
        guard let duration = try? await asset.load(.duration), duration.isNumeric else { return nil }
        return Int64(duration.seconds * 1000)
    }

    private static func copy(_ asset: AVURLAsset, to destination: URL) async -> Bool {
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            return false
        }
        do {
            try await export.export(to: destination, as: .m4a)
            return true
        } catch {
            try? FileManager.default.removeItem(at: destination)
            return false
        }
    }
}
