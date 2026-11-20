import CryptoKit
import Observation

/// The vault's door: whether it's open, and why it won't open if it won't. Opening takes the key
/// from the Keychain, which asks for Face ID or the passcode; locking forgets it again.
@MainActor
@Observable
final class Vault {
    private(set) var isOpen = false
    /// The Keychain no longer has the vault's key, so the tapes inside can't be opened again.
    private(set) var isKeyLost = false
    private(set) var passcodeIsSet: Bool

    @ObservationIgnored private let keychain: VaultKeychain
    @ObservationIgnored private let store: VaultStore
    @ObservationIgnored private let library: TapeLibrary
    @ObservationIgnored private let player: Player
    @ObservationIgnored private let captions: CaptionQueue
    /// Two taps on UNLOCK must not make two keys for a new vault.
    @ObservationIgnored private var opening = false

    init(keychain: VaultKeychain, store: VaultStore, library: TapeLibrary, player: Player, captions: CaptionQueue) {
        self.keychain = keychain
        self.store = store
        self.library = library
        self.player = player
        self.captions = captions
        passcodeIsSet = keychain.passcodeIsSet
    }

    /// The passcode may have been set or turned off in Settings while Dic2Phone was away.
    func checkPasscode() {
        passcodeIsSet = keychain.passcodeIsSet
    }

    func unlock() async -> VaultUnlock {
        guard !isOpen else { return .opened }
        guard !opening else { return .cancelled }
        checkPasscode()
        guard passcodeIsSet else { return .noPasscode }
        opening = true
        defer { opening = false }
        do {
            try await store.open(with: readKey())
        } catch VaultKeyError.cancelled {
            return .cancelled
        } catch VaultKeyError.missing, CryptoKitError.authenticationFailure {
            isKeyLost = true
            return .keyLost
        } catch {
            return .failed
        }
        isOpen = true
        await library.reload()
        return .opened
    }

    /// Hides the vault's tapes and stops any of them that is playing or being captioned straight
    /// away, then forgets the key.
    func lock() async {
        isOpen = false
        player.letGo(of: library.vault)
        captions.forgetVault()
        library.forgetVault()
        await store.close()
    }

    func reset() async {
        await lock()
        await store.reset()
        keychain.forgetKey()
        isKeyLost = false
        await library.reload()
    }

    private func readKey() async throws -> SymmetricKey {
        let reason = String(localized: "Open the vault of locked tapes")
        return store.exists ? try await keychain.key(reason: reason) : try await keychain.newKey(reason: reason)
    }
}
