/// Why captions couldn't be made. Shown to the user only as a plain message, never with
/// system details (CWE-209).
enum CaptionError: Error {
    case modelUnreadable
    case transcriptionFailed
}
