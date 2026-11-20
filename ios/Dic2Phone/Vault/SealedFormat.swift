import Foundation

/// The layout of a sealed vault file, the same as the Android app's:
///
///     header:  "D2PV" | version (1) | 3 reserved | file id (16)           = 24 bytes
///     records: nonce (12) | AES-GCM ciphertext of one chunk (≤ 64 KiB) | tag (16)
///
/// Chunks let a tape play from the middle without decrypting all of it. Each record is
/// authenticated together with its file id, its index and whether it's the last, so records
/// can't be reordered, swapped in from another file, or cut off the end unnoticed. There is
/// always a last record, even an empty one, so that cut is detectable too.
enum SealedFormat {
    static let chunkSize = 64 * 1024
    static let nonceSize = 12
    static let tagSize = 16
    static let recordOverhead = nonceSize + tagSize
    static let recordSize = chunkSize + recordOverhead
    static let fileIDSize = 16
    static let headerSize = 24

    private static let magic = Data("D2PV".utf8)
    private static let version: UInt8 = 1
    private static let reservedSize = 3

    static func header(fileID: Data) -> Data {
        magic + [version] + Data(count: reservedSize) + fileID
    }

    /// The file id from a header, or nil if it isn't a sealed file this version can read.
    static func fileID(fromHeader header: Data) -> Data? {
        guard header.count == headerSize,
              header.prefix(magic.count) == magic,
              header.dropFirst(magic.count).first == version
        else { return nil }
        return Data(header.suffix(fileIDSize))
    }

    static func associatedData(fileID: Data, chunk: UInt64, isLast: Bool) -> Data {
        let index = (0..<8).reversed().map { UInt8(truncatingIfNeeded: chunk >> ($0 * 8)) }
        return fileID + index + [isLast ? 1 : 0]
    }
}
