import Foundation

/// The random name a tape's files get in the vault, 24 lowercase hex digits. Random so the
/// folder doesn't give away when its tapes were recorded; validated like `TapeID`, so a name
/// read back from the index can never point outside the vault folder (CWE-22).
struct SealedName: Hashable, Sendable {
    private static let byteCount = 12
    private static let hexDigits = Set("0123456789abcdef")

    let value: String

    init?(_ value: String) {
        guard value.count == Self.byteCount * 2, value.allSatisfy(Self.hexDigits.contains) else { return nil }
        self.value = value
    }

    private init(validated value: String) {
        self.value = value
    }

    static func random() -> SealedName {
        SealedName(validated: RandomBytes.make(byteCount).map { String(format: "%02x", $0) }.joined())
    }
}
