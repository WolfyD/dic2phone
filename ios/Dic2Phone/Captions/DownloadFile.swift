import CryptoKit
import Foundation

/// A download being written to disk, hashed as it arrives. It refuses to grow past the size
/// it should have, so a wrong or hostile answer can't fill the phone.
final class DownloadFile {
    private let handle: FileHandle
    private let sizeLimit: Int64
    private var hasher = SHA256()
    private(set) var byteCount: Int64 = 0

    init(at url: URL, sizeLimit: Int64) throws {
        guard FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil) else {
            throw CaptionError.modelUnsaved
        }
        handle = try FileHandle(forWritingTo: url)
        self.sizeLimit = sizeLimit
    }

    func append(_ data: Data) throws {
        byteCount += Int64(data.count)
        guard byteCount <= sizeLimit else { throw CaptionError.downloadCorrupted }
        hasher.update(data: data)
        do {
            try handle.write(contentsOf: data)
        } catch {
            throw CaptionError.modelUnsaved
        }
    }

    /// Closes the file.
    /// - Returns: the SHA-256 of everything written, in lower-case hex.
    func finish() throws -> String {
        try handle.close()
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
