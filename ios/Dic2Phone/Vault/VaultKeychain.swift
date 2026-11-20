import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// The vault's data key, kept in the Keychain on this phone only, and only handed out after
/// Face ID or the passcode. It never goes to iCloud or a backup, and turning off the passcode
/// makes iOS delete it.
struct VaultKeychain: Sendable {
    private static let service = "com.dic2phone.vault"
    private static let account = "data-key"
    private static let keyByteCount = 32

    var passcodeIsSet: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Asks for Face ID or the passcode, then reads the key.
    func key(reason: String) async throws -> SymmetricKey {
        try await withCheckedThrowingContinuation { continuation in
            // Reading waits for as long as the Face ID sheet is up, so it can't be on the main thread.
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try Self.readKey(reason: reason) })
            }
        }
    }

    /// Replaces any old key with a new random one, then reads it back, which asks for Face ID
    /// or the passcode, so even a new vault only opens for the phone's owner.
    func newKey(reason: String) async throws -> SymmetricKey {
        forgetKey()
        try Self.add(RandomBytes.make(Self.keyByteCount))
        return try await key(reason: reason)
    }

    func forgetKey() {
        SecItemDelete(Self.itemQuery as CFDictionary)
    }

    private static var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func add(_ secret: Data) throws {
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, nil
        ) else { throw VaultKeyError.failed }
        var query = itemQuery
        query[kSecValueData as String] = secret
        query[kSecAttrAccessControl as String] = access
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw VaultKeyError.failed }
    }

    private static func readKey(reason: String) throws -> SymmetricKey {
        let context = LAContext()
        context.localizedReason = reason
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let secret = result as? Data, secret.count == keyByteCount else { throw VaultKeyError.failed }
            return SymmetricKey(data: secret)
        case errSecUserCanceled:
            throw VaultKeyError.cancelled
        case errSecItemNotFound:
            throw VaultKeyError.missing
        default:
            throw VaultKeyError.failed
        }
    }
}
