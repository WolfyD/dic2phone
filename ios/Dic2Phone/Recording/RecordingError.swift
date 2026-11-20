import Foundation

/// Why a recording couldn't run. Shown to the user only as a plain message, never with
/// system details (CWE-209).
enum RecordingError: Error {
    case micUnavailable
    case writerFailed
}
