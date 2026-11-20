@testable import Dic2Phone

extension Tape {
    /// A deck tape recorded at `stamp` ("2026-11-19_14-03-22").
    static func fixture(_ stamp: String, title: String = "", durationMs: Int64 = 0, isNew: Bool = false) -> Tape {
        Tape(
            id: TapeID(stamp + "." + TapeID.fileExtension)!,
            rack: .deck,
            durationMs: durationMs,
            sizeBytes: 0,
            isNew: isNew,
            title: title,
            flags: []
        )
    }
}
