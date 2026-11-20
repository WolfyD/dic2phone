import Foundation

/// What saving a half-written tape needs besides the sound: when it started, whether it was
/// noise-activated, and its flags. Written next to the tape while it records.
struct RescueNote: Codable, Equatable {
    var startedAtMs: Int64
    var vox: Bool
    var flags: [Int64]

    func write(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    static func read(from url: URL) -> RescueNote? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RescueNote.self, from: data)
    }
}
