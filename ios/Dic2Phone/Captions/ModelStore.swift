import Foundation

/// The speech models on this phone: downloading one, checking it is the pinned file, and
/// deleting them all.
struct ModelStore: Sendable {
    private static let pieceSize = 256 * 1024

    let storage: Storage
    let session: URLSession

    func isDownloaded(_ model: SpeechModel) -> Bool {
        let size = try? storage.modelURL(model).resourceValues(forKeys: [.fileSizeKey]).fileSize
        return size.map(Int64.init) == model.sizeBytes
    }

    func url(of model: SpeechModel) -> URL {
        storage.modelURL(model)
    }

    /// Keeps the model only if every byte matches the pinned SHA-256 (CWE-494).
    /// - Parameter progress: percent done, called each time it changes.
    func download(_ model: SpeechModel, progress: @Sendable (Int) async -> Void) async throws {
        let part = storage.modelDownloadURL(model)
        defer { try? FileManager.default.removeItem(at: part) }
        let digest = try await receive(model, into: part, progress: progress)
        guard digest == model.sha256 else { throw CaptionError.downloadCorrupted }
        do {
            try? FileManager.default.removeItem(at: storage.modelURL(model))
            try FileManager.default.moveItem(at: part, to: storage.modelURL(model))
        } catch {
            throw CaptionError.modelUnsaved
        }
    }

    func deleteAll() {
        for model in SpeechModel.allCases {
            try? FileManager.default.removeItem(at: storage.modelURL(model))
            try? FileManager.default.removeItem(at: storage.modelDownloadURL(model))
        }
    }

    /// - Returns: the SHA-256 of what arrived.
    private func receive(_ model: SpeechModel, into part: URL, progress: @Sendable (Int) async -> Void) async throws -> String {
        let bytes = try await open(model)
        let file = try DownloadFile(at: part, sizeLimit: model.sizeBytes)
        do {
            try await copy(bytes, to: file, expecting: model.sizeBytes, progress: progress)
        } catch let error as URLError {
            throw Self.reason(for: error)
        }
        guard file.byteCount == model.sizeBytes else { throw CaptionError.downloadCorrupted }
        return try file.finish()
    }

    /// Writes in pieces: one byte at a time would be far too slow for the disk and the hash.
    private func copy(
        _ bytes: URLSession.AsyncBytes,
        to file: DownloadFile,
        expecting size: Int64,
        progress: @Sendable (Int) async -> Void
    ) async throws {
        var piece = Data(capacity: Self.pieceSize)
        var percent = -1
        for try await byte in bytes {
            piece.append(byte)
            guard piece.count == Self.pieceSize else { continue }
            try file.append(piece)
            piece.removeAll(keepingCapacity: true)
            let now = Int(file.byteCount * 100 / size)
            if now != percent {
                percent = now
                await progress(now)
            }
        }
        try file.append(piece)
    }

    private func open(_ model: SpeechModel) async throws -> URLSession.AsyncBytes {
        guard let source = model.downloadURL else { throw CaptionError.downloadUnreachable }
        do {
            let (bytes, response) = try await session.bytes(from: source)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw CaptionError.downloadFailed(status: status) }
            return bytes
        } catch let error as URLError {
            throw Self.reason(for: error)
        }
    }

    private static func reason(for error: URLError) -> Error {
        error.code == .cancelled ? CancellationError() : CaptionError.downloadUnreachable
    }
}
