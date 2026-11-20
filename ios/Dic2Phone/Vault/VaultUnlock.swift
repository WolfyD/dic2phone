/// How a try at opening the vault went.
enum VaultUnlock {
    case opened
    case cancelled
    /// The vault needs a passcode on the phone, and there isn't one.
    case noPasscode
    /// The key the vault was sealed with is gone; only a reset helps.
    case keyLost
    case failed
}
