import Foundation

/// Why captions couldn't be made. Shown to the user only as a plain message, never with
/// system details (CWE-209).
enum CaptionError: Error, Equatable {
    case modelUnreadable
    case transcriptionFailed
    case downloadFailed(status: Int)
    case downloadUnreachable
    case downloadCorrupted
    case modelUnsaved
    case vaultLocked
    case tapeUnreadable

    var message: String {
        switch self {
        case .modelUnreadable: String(localized: "Couldn't load the speech model")
        case .transcriptionFailed: String(localized: "Transcribing failed")
        case .downloadFailed(let status): String(localized: "Model download failed (HTTP \(status))")
        case .downloadUnreachable: String(localized: "Couldn't reach the model download, check the connection")
        case .downloadCorrupted: String(localized: "Model download was corrupted, try again")
        case .modelUnsaved: String(localized: "Couldn't save the model")
        case .vaultLocked: String(localized: "Open the vault first")
        case .tapeUnreadable: String(localized: "Couldn't read the tape")
        }
    }
}
