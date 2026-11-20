/// When new tapes get captions without being asked. Raw values match the Android app's, which
/// also has WHEN IDLE (2). Here tapes can't be read while the phone is locked, which is when
/// it sits idle.
enum AutoCaptions: Int, CaseIterable, Sendable {
    case off = 0
    case afterRecording = 1

    var label: String {
        switch self {
        case .off: String(localized: "OFF")
        case .afterRecording: String(localized: "AFTER REC")
        }
    }
}
