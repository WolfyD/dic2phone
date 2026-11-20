import CryptoKit
import Foundation

/// A sealed file and the key that opens it, safe to hand between threads: each reader opens its
/// own file handle.
struct SealedFile: Sendable {
    let url: URL
    let key: SymmetricKey

    func reader() throws -> SealedFileReader {
        try SealedFileReader(url: url, key: key)
    }
}
