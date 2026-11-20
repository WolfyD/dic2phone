/// When new tapes get captions without being asked. Raw values match the Android app's.
enum AutoCaptions: Int, CaseIterable, Sendable {
    case off = 0
    case afterRecording = 1
    case whenIdle = 2

    var label: String {
        switch self {
        case .off: String(localized: "OFF")
        case .afterRecording: String(localized: "AFTER REC")
        case .whenIdle: String(localized: "WHEN IDLE")
        }
    }
}
