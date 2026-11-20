import CryptoKit
import Foundation

/// Writes a sealed file chunk by chunk, so a long tape never sits whole in memory.
final class SealedFileWriter {
    private let handle: FileHandle
    private let key: SymmetricKey
    private let fileID = RandomBytes.make(SealedFormat.fileIDSize)
    private var pending = Data()
    private var chunk: UInt64 = 0

    init(creating url: URL, key: SymmetricKey) throws {
        self.key = key
        let created = FileManager.default.createFile(
            atPath: url.path(percentEncoded: false),
            contents: SealedFormat.header(fileID: fileID),
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
        )
        guard created else { throw SealedFileError.unwritable }
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    deinit {
        try? handle.close()
    }

    func write(_ data: Data) throws {
        pending.append(data)
        while pending.count >= SealedFormat.chunkSize {
            try seal(pending.prefix(SealedFormat.chunkSize), isLast: false)
            pending = Data(pending.dropFirst(SealedFormat.chunkSize))
        }
    }

    func finish() throws {
        try seal(pending, isLast: true)
        pending = Data()
        try handle.synchronize()
        try handle.close()
    }

    private func seal(_ plain: Data, isLast: Bool) throws {
        let associated = SealedFormat.associatedData(fileID: fileID, chunk: chunk, isLast: isLast)
        guard let record = try AES.GCM.seal(plain, using: key, authenticating: associated).combined else {
            throw SealedFileError.unwritable
        }
        try handle.write(contentsOf: record)
        chunk += 1
    }
}

extension SealedFileWriter {
    static func seal(_ data: Data, to url: URL, key: SymmetricKey) throws {
        let writer = try SealedFileWriter(creating: url, key: key)
        try writer.write(data)
        try writer.finish()
    }

    static func seal(contentsOf source: URL, to url: URL, key: SymmetricKey) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let writer = try SealedFileWriter(creating: url, key: key)
        while let data = try input.read(upToCount: SealedFormat.chunkSize), !data.isEmpty {
            try writer.write(data)
        }
        try writer.finish()
    }
}
