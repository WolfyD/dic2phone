import Foundation

/// The app's folders, and the only place file URLs for tapes are made.
///
/// Everything is created with `completeUnlessOpen` protection: a dictaphone has to start new
/// tapes while the phone is locked, but nothing can be read back until it is unlocked.
/// New files inherit their folder's protection.
struct Storage: Sendable {
    static let protection = [FileAttributeKey.protectionKey: FileProtectionType.completeUnlessOpen]
    private static let effectCopySuffix = "_tape.m4a"

    let deck: URL
    let shelf: URL
    let recording: URL
    let meta: URL
    let captions: URL
    /// Downloaded speech models.
    let models: URL
    let vault: URL
    /// Plain copies on their way out of the vault: to the shelf, or to the share sheet.
    let unsealed: URL
    /// Tapes' effect copies, in a folder per combination of effects. In the caches, which
    /// iOS empties by itself when storage runs low; they can always be made again.
    let effectCopies: URL
    /// Effect copies being made, until they're finished.
    let effectDrafts: URL

    init(support: URL, documents: URL, temporary: URL, caches: URL) {
        deck = support.appending(path: "deck", directoryHint: .isDirectory)
        recording = support.appending(path: "recording", directoryHint: .isDirectory)
        meta = support.appending(path: "meta", directoryHint: .isDirectory)
        captions = support.appending(path: "captions", directoryHint: .isDirectory)
        models = support.appending(path: "models", directoryHint: .isDirectory)
        vault = support.appending(path: "vault", directoryHint: .isDirectory)
        shelf = documents.appending(path: "Shelf", directoryHint: .isDirectory)
        unsealed = temporary.appending(path: "unsealed", directoryHint: .isDirectory)
        effectCopies = caches.appending(path: "effects", directoryHint: .isDirectory)
        effectDrafts = caches.appending(path: "effect-drafts", directoryHint: .isDirectory)
    }

    static func standard() throws -> Storage {
        let files = FileManager.default
        let support = try files.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let documents = try files.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let caches = try files.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return Storage(support: support, documents: documents, temporary: files.temporaryDirectory, caches: caches)
    }

    func prepare() throws {
        for folder in [deck, shelf, recording, meta, captions, models, vault, unsealed, effectCopies, effectDrafts] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: Self.protection)
        }
        // The vault's key never leaves this phone, so a backup of the sealed tapes could never
        // be opened anywhere else; keeping them out of backups also keeps them off iCloud.
        try Self.excludeFromBackup(vault)
        // Models can be downloaded again, and Apple asks that such files stay out of backups.
        try Self.excludeFromBackup(models)
    }

    private static func excludeFromBackup(_ folder: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = folder
        try excluded.setResourceValues(values)
    }

    func folder(for rack: Rack) -> URL {
        switch rack {
        case .deck: deck
        case .shelf: shelf
        case .vault: vault
        }
    }

    /// Where a plain tape's file is. Vault tapes are sealed under a `SealedName` instead.
    func tapeURL(_ id: TapeID, in rack: Rack) -> URL {
        folder(for: rack).appending(path: id.fileName, directoryHint: .notDirectory)
    }

    func metaURL(_ id: TapeID) -> URL {
        meta.appending(path: id.baseName + ".json", directoryHint: .notDirectory)
    }

    /// A plain tape's captions, as SubRip text.
    func captionsURL(_ id: TapeID) -> URL {
        captions.appending(path: id.baseName + ".srt", directoryHint: .notDirectory)
    }

    func modelURL(_ model: SpeechModel) -> URL {
        models.appending(path: model.fileName, directoryHint: .notDirectory)
    }

    /// A model being downloaded, until it's verified.
    func modelDownloadURL(_ model: SpeechModel) -> URL {
        models.appending(path: model.fileName + ".part", directoryHint: .notDirectory)
    }

    func recordingURL(_ id: TapeID) -> URL {
        recording.appending(path: id.fileName, directoryHint: .notDirectory)
    }

    func rescueNoteURL(_ id: TapeID) -> URL {
        recording.appending(path: id.baseName + ".json", directoryHint: .notDirectory)
    }

    var vaultIndexURL: URL {
        vault.appending(path: "index", directoryHint: .notDirectory)
    }

    func sealedTapeURL(_ name: SealedName) -> URL {
        vault.appending(path: name.value + ".d2pv", directoryHint: .notDirectory)
    }

    func sealedMetaURL(_ name: SealedName) -> URL {
        vault.appending(path: name.value + ".meta", directoryHint: .notDirectory)
    }

    func sealedCaptionsURL(_ name: SealedName) -> URL {
        vault.appending(path: name.value + ".cc", directoryHint: .notDirectory)
    }

    /// A tape being sealed, until it's complete.
    func sealingURL(_ name: SealedName) -> URL {
        vault.appending(path: name.value + ".part", directoryHint: .notDirectory)
    }

    /// A tape being taken out of the vault, until it's complete.
    func unsealingURL(_ name: SealedName) -> URL {
        unsealed.appending(path: name.value + ".part", directoryHint: .notDirectory)
    }

    /// A vault tape's plain copy for the share sheet, under its real name.
    func sendingURL(_ id: TapeID) -> URL {
        unsealed.appending(path: id.fileName, directoryHint: .notDirectory)
    }

    /// A plain copy of a vault tape's captions for the share sheet.
    func sendingCaptionsURL(_ id: TapeID) -> URL {
        unsealed.appending(path: id.baseName + ".srt", directoryHint: .notDirectory)
    }

    /// The folder for copies made with one combination of effects, named by its mask.
    func effectCopyFolder(mask: Int) -> URL {
        effectCopies.appending(path: "fx\(mask)", directoryHint: .isDirectory)
    }

    /// A plain tape's effect copy, under the tape's name with `_tape` added, as Android sends it.
    func effectCopyURL(_ id: TapeID, mask: Int) -> URL {
        effectCopyFolder(mask: mask).appending(path: id.baseName + Self.effectCopySuffix, directoryHint: .notDirectory)
    }

    func effectDraftURL(_ id: TapeID, mask: Int) -> URL {
        effectDrafts.appending(path: "fx\(mask)-" + id.baseName + Self.effectCopySuffix, directoryHint: .notDirectory)
    }

    /// The tape an effect copy was made from; nil for any other file.
    func tapeID(ofEffectCopy copy: URL) -> TapeID? {
        let name = copy.lastPathComponent
        guard name.hasSuffix(Self.effectCopySuffix) else { return nil }
        return TapeID(String(name.dropLast(Self.effectCopySuffix.count)) + "." + TapeID.fileExtension)
    }

    /// A name for a tape starting at `date` that no tape anywhere uses yet.
    func unusedTapeID(startedAt date: Date) -> TapeID {
        var copy = 1
        while true {
            let id = TapeID(startedAt: date, copy: copy)
            let candidates = Rack.plain.map { tapeURL(id, in: $0) } + [recordingURL(id)]
            if !candidates.contains(where: { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }) {
                return id
            }
            copy += 1
        }
    }

    /// Valid tape IDs found in `folder`; anything else there is ignored.
    func tapeIDs(in folder: URL) -> [TapeID] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.compactMap(TapeID.init)
    }
}
