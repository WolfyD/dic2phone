import AppIntents

/// REC from outside the app: the Action Button, Siri, Back Tap or a shortcut. Like tapping REC
/// on the deck, it starts a tape locked on, or stops the one being recorded.
struct RecordIntent: AppIntent {
    static let title: LocalizedStringResource = "Record or Stop"
    static let description = IntentDescription("Starts recording a tape, locked on. If a tape is being recorded, stops it.")
    /// iOS lets an app start the mic only while it's on screen.
    static let openAppWhenRun = true

    /// Nil when the app couldn't open its storage; it shows why once it's open.
    @Dependency private var recorder: Recorder?

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let recorder else { return .result() }
        if recorder.state.recording {
            recorder.stop()
        } else {
            recorder.start(source: "intent", latched: true)
        }
        return .result()
    }
}
