import AppIntents

/// Stops a recording from outside the app, without bringing it to the screen.
struct StopRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Recording"
    static let description = IntentDescription("Stops the tape being recorded and puts it on the deck.")

    @Dependency private var recorder: Recorder?

    @MainActor
    func perform() async throws -> some IntentResult {
        recorder?.stop()
        return .result()
    }
}
