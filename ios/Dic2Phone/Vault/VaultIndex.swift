import CryptoKit
import Foundation

/// The vault's list of tapes, encrypted as a whole, so even the tapes' names and dates stay
/// hidden while it's locked.
enum VaultIndex {
    private static let associatedData = Data("index".utf8)

    static func seal(_ entries: [VaultEntry], key: SymmetricKey) throws -> Data {
        let json = try JSONEncoder().encode(entries)
        guard let sealed = try AES.GCM.seal(json, using: key, authenticating: associatedData).combined else {
            throw SealedFileError.unwritable
        }
        return sealed
    }

    static func open(_ data: Data, key: SymmetricKey) throws -> [VaultEntry] {
        let json = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: associatedData)
        return try JSONDecoder().decode([VaultEntry].self, from: json)
    }
}
