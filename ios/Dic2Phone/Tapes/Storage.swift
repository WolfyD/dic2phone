import Foundation

/// The app's folders, and the only place file URLs for tapes are made.
///
/// Everything is created with `completeUnlessOpen` protection: a dictaphone has to start new
/// tapes while the phone is locked, but nothing can be read back until it is unlocked.
/// New files inherit their folder's protection.
struct Storage: Sendable {
    let deck: URL
    let shelf: URL
    let recording: URL
    let meta: URL

    init(support: URL, documents: URL) {
        deck = support.appending(path: "deck", directoryHint: .isDirectory)
        recording = support.appending(path: "recording", directoryHint: .isDirectory)
        meta = support.appending(path: "meta", directoryHint: .isDirectory)
        shelf = documents.appending(path: "Shelf", directoryHint: .isDirectory)
    }

    static func standard() throws -> Storage {
        let files = FileManager.default
        let support = try files.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let documents = try files.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return Storage(support: support, documents: documents)
    }

    func prepare() throws {
        let protection = [FileAttributeKey.protectionKey: FileProtectionType.completeUnlessOpen]
        for folder in [deck, shelf, recording, meta] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: protection)
        }
    }

    func folder(for rack: Rack) -> URL {
        switch rack {
        case .deck: deck
        case .shelf: shelf
        }
    }

    func tapeURL(_ id: TapeID, in rack: Rack) -> URL {
        folder(for: rack).appending(path: id.fileName, directoryHint: .notDirectory)
    }

    func metaURL(_ id: TapeID) -> URL {
        meta.appending(path: id.baseName + ".json", directoryHint: .notDirectory)
    }

    func recordingURL(_ id: TapeID) -> URL {
        recording.appending(path: id.fileName, directoryHint: .notDirectory)
    }

    func rescueNoteURL(_ id: TapeID) -> URL {
        recording.appending(path: id.baseName + ".json", directoryHint: .notDirectory)
    }

    /// A name for a tape starting at `date` that no tape anywhere uses yet.
    func unusedTapeID(startedAt date: Date) -> TapeID {
        var copy = 1
        while true {
            let id = TapeID(startedAt: date, copy: copy)
            let candidates = Rack.allCases.map { tapeURL(id, in: $0) } + [recordingURL(id)]
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
