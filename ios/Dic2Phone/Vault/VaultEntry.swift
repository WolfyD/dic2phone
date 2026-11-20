import Foundation

/// One tape in the vault's index: which tape it was, and where its sealed files are. Stored
/// with the same keys as the Android app.
struct VaultEntry: Equatable, Sendable {
    let id: TapeID
    let name: SealedName
    let durationMs: Int64
    let sizeBytes: Int64
    let addedAtMs: Int64
}

extension VaultEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name = "f"
        case durationMs = "dur"
        case sizeBytes = "size"
        case addedAtMs = "added"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = TapeID(try c.decode(String.self, forKey: .id)) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Not a tape name")
        }
        guard let name = SealedName(try c.decode(String.self, forKey: .name)) else {
            throw DecodingError.dataCorruptedError(forKey: .name, in: c, debugDescription: "Not a sealed name")
        }
        self.id = id
        self.name = name
        durationMs = try c.decode(Int64.self, forKey: .durationMs)
        sizeBytes = try c.decode(Int64.self, forKey: .sizeBytes)
        addedAtMs = try c.decodeIfPresent(Int64.self, forKey: .addedAtMs) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id.fileName, forKey: .id)
        try c.encode(name.value, forKey: .name)
        try c.encode(durationMs, forKey: .durationMs)
        try c.encode(sizeBytes, forKey: .sizeBytes)
        try c.encode(addedAtMs, forKey: .addedAtMs)
    }
}
