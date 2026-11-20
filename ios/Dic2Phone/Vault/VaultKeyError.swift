/// Why the vault's key couldn't be read from the Keychain.
enum VaultKeyError: Error {
    /// The user closed the Face ID or passcode sheet.
    case cancelled
    /// The key isn't there any more: iOS deletes it when the passcode is turned off.
    case missing
    case failed
}
