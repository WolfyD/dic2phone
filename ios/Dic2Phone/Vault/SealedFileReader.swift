import CryptoKit
import Foundation

/// Reads a sealed file from any position, decrypting only the chunks it needs.
final class SealedFileReader {
    /// How many bytes of plain content the file holds.
    let size: Int64

    private let handle: FileHandle
    private let key: SymmetricKey
    private let fileID: Data
    private let chunkCount: UInt64
    private var cachedIndex: UInt64?
    private var cachedChunk = Data()

    init(url: URL, key: SymmetricKey) throws {
        handle = try FileHandle(forReadingFrom: url)
        self.key = key
        guard let header = try handle.read(upToCount: SealedFormat.headerSize),
              let fileID = SealedFormat.fileID(fromHeader: header)
        else { throw SealedFileError.notSealed }
        self.fileID = fileID
        let body = Int64(try handle.seekToEnd()) - Int64(SealedFormat.headerSize)
        let record = Int64(SealedFormat.recordSize)
        let chunks = (body + record - 1) / record
        size = body - chunks * Int64(SealedFormat.recordOverhead)
        guard chunks > 0, size >= 0 else { throw SealedFileError.damaged }
        chunkCount = UInt64(chunks)
    }

    deinit {
        try? handle.close()
    }

    /// Up to `count` bytes from `offset`; fewer only at the end of the file.
    func read(from offset: Int64, count: Int) throws -> Data {
        guard offset >= 0, count >= 0 else { throw SealedFileError.damaged }
        let end = min(offset + Int64(count), size)
        var result = Data()
        var position = offset
        while position < end {
            let chunkSize = Int64(SealedFormat.chunkSize)
            let plain = try chunk(UInt64(position / chunkSize))
            let start = Int(position % chunkSize)
            let length = min(plain.count - start, Int(end - position))
            guard length > 0 else { throw SealedFileError.damaged }
            result.append(plain.dropFirst(start).prefix(length))
            position += Int64(length)
        }
        return result
    }

    /// Everything, with every record checked, including an empty last one.
    func readAll() throws -> Data {
        try (0..<chunkCount).reduce(into: Data()) { all, index in
            all.append(try chunk(index))
        }
    }

    /// Writes the plain content to a new file at `destination`.
    func copy(to destination: URL) throws {
        let created = FileManager.default.createFile(
            atPath: destination.path(percentEncoded: false),
            contents: nil,
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
        )
        guard created else { throw SealedFileError.unwritable }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        for index in 0..<chunkCount {
            try output.write(contentsOf: chunk(index))
        }
        try output.synchronize()
    }

    private func chunk(_ index: UInt64) throws -> Data {
        if index == cachedIndex { return cachedChunk }
        guard index < chunkCount else { throw SealedFileError.damaged }
        try handle.seek(toOffset: UInt64(SealedFormat.headerSize) + index * UInt64(SealedFormat.recordSize))
        guard let record = try handle.read(upToCount: SealedFormat.recordSize) else { throw SealedFileError.damaged }
        let isLast = index == chunkCount - 1
        let associated = SealedFormat.associatedData(fileID: fileID, chunk: index, isLast: isLast)
        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: record), using: key, authenticating: associated)
        // Every chunk but the last is full; anything else would shift every offset after it.
        guard isLast || plain.count == SealedFormat.chunkSize else { throw SealedFileError.damaged }
        cachedIndex = index
        cachedChunk = plain
        return plain
    }
}
