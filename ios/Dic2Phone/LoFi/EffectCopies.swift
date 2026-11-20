import Foundation

/// The tapes' effect copies. Each is made once and kept, since a long tape takes a while to
/// make, and they go with their tape. Only plain tapes have them: a vault tape's copy would be
/// its sound left unencrypted on disk.
actor EffectCopies {
    /// Days a copy is kept without being played; 0 keeps it until cleared.
    static let keepChoices = [0, 30, 90, 180]
    private static let day: TimeInterval = 86_400

    nonisolated let storage: Storage
    private var making: [URL: Task<URL?, Never>] = [:]

    init(storage: Storage) {
        self.storage = storage
    }

    nonisolated func ready(_ id: TapeID, with effects: TapeEffects) -> URL? {
        let copy = storage.effectCopyURL(id, mask: effects.mask)
        return Self.size(of: copy) > 0 ? copy : nil
    }

    /// The copy of the plain tape at `tape`, made first if need be. However many ask at once,
    /// it's made once, and it carries on being made if they stop waiting.
    func copy(of id: TapeID, from tape: URL, with effects: TapeEffects) async -> URL? {
        if let ready = ready(id, with: effects) { return ready }
        let copy = storage.effectCopyURL(id, mask: effects.mask)
        if let underway = making[copy] { return await underway.value }
        let draft = storage.effectDraftURL(id, mask: effects.mask)
        let task = Task.detached(priority: .utility) {
            await Self.make(from: tape, draft: draft, copy: copy, with: effects)
        }
        making[copy] = task
        let made = await task.value
        if making[copy] == task { making[copy] = nil }
        return made
    }

    /// Played: its days without being played start again.
    func markPlayed(_ copy: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: copy.path(percentEncoded: false))
    }

    /// Tapes deleted or locked in the vault: their copies go too, even ones being made.
    func forget(_ ids: Set<TapeID>) async {
        await stopMaking { storage.tapeID(ofEffectCopy: $0).map(ids.contains) ?? false }
        for (copy, id) in copies() where ids.contains(id) {
            try? FileManager.default.removeItem(at: copy)
        }
    }

    /// Deletes copies whose tape is gone, those not played for `unplayedDays` (unless 0), and
    /// drafts left behind when the app was closed in the middle of making one.
    func tidy(keeping tapes: Set<TapeID>, unplayedDays: Int, now: Date) {
        let cutoff = unplayedDays > 0 ? now.addingTimeInterval(-Double(unplayedDays) * Self.day) : nil
        for (copy, id) in copies() {
            let unplayed = cutoff.map { Self.modified(copy) < $0 } ?? false
            if !tapes.contains(id) || unplayed {
                try? FileManager.default.removeItem(at: copy)
            }
        }
        if making.isEmpty {
            Self.removeContents(of: storage.effectDrafts)
        }
    }

    func usage() -> EffectCopyUsage {
        copies().reduce(into: EffectCopyUsage()) { usage, entry in
            usage.count += 1
            usage.bytes += Self.size(of: entry.copy)
        }
    }

    /// CLEAR NOW: every copy, and any being made.
    func clear() async {
        await stopMaking { _ in true }
        Self.removeContents(of: storage.effectCopies)
        Self.removeContents(of: storage.effectDrafts)
    }

    /// Waits for them to stop, so none can land after its tape has gone.
    private func stopMaking(where shouldStop: (URL) -> Bool) async {
        let stopping = making.filter { shouldStop($0.key) }
        for (copy, task) in stopping {
            task.cancel()
            making[copy] = nil
        }
        for task in stopping.values {
            _ = await task.value
        }
    }

    private func copies() -> [(copy: URL, id: TapeID)] {
        Self.contents(of: storage.effectCopies).flatMap { folder in
            Self.contents(of: folder).compactMap { copy in
                storage.tapeID(ofEffectCopy: copy).map { (copy, $0) }
            }
        }
    }

    private static func make(from tape: URL, draft: URL, copy: URL, with effects: TapeEffects) async -> URL? {
        let files = FileManager.default
        try? files.removeItem(at: draft)
        let folder = copy.deletingLastPathComponent()
        guard (try? files.createDirectory(at: folder, withIntermediateDirectories: true, attributes: Storage.protection)) != nil,
              await EffectRenderer.render(tape, to: draft, with: effects),
              !Task.isCancelled,
              (try? files.moveItem(at: draft, to: copy)) != nil else {
            try? files.removeItem(at: draft)
            return nil
        }
        return copy
    }

    private static func contents(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }

    private static func removeContents(of folder: URL) {
        for item in contents(of: folder) {
            try? FileManager.default.removeItem(at: item)
        }
    }

    private static func size(of file: URL) -> Int64 {
        Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private static func modified(_ file: URL) -> Date {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
