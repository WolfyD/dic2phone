import AVFoundation

/// Builds the app's services once, wired to each other, and runs the work that belongs to the
/// app rather than to a screen: saving cut-off tapes at launch, and stopping for phone calls.
@MainActor
final class AppModel {
    let settings: Settings
    let library: TapeLibrary
    let feedback: Feedback
    let player: Player
    let recorder: Recorder
    let flagKey: FlagKey

    private let audioSession: AudioSession
    private let rescue: TapeRescue
    private let leftovers: [TapeID]

    init() throws {
        let storage = try Storage.standard()
        try storage.prepare()
        let defaults = UserDefaults.standard
        let store = TapeStore(storage: storage)
        let audioSession = AudioSession()
        let settings = Settings(defaults: defaults)
        let library = TapeLibrary(store: store, heard: HeardList(defaults: defaults))
        let feedback = Feedback(settings: settings, audioSession: audioSession, haptics: Haptics())
        let player = Player(settings: settings, store: store, library: library, feedback: feedback, audioSession: audioSession)
        self.settings = settings
        self.library = library
        self.feedback = feedback
        self.player = player
        self.audioSession = audioSession
        recorder = Recorder(
            settings: settings, store: store, library: library, feedback: feedback,
            audioSession: audioSession, player: player, makeMic: { EngineMic() }
        )
        flagKey = FlagKey(player: player, library: library)
        rescue = TapeRescue(store: store, device: DeviceLabel.current)
        leftovers = rescue.leftovers()
    }

    func start() async {
        // If this fails, activating the session to record or play fails too, and says so there.
        try? audioSession.configure()
        _ = await rescue.rescue(leftovers)
        await library.reload()
    }

    /// A call or an alarm takes the audio away: stop cleanly, so the tape so far is saved,
    /// instead of recording silence.
    func stopForInterruptions() async {
        let interruptions = NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification)
        for await notification in interruptions where AudioSession.isInterruptionStart(notification) {
            recorder.stop()
            player.stop()
        }
    }

    /// Clicks are silent while recording: they would end up on the tape.
    var keyClick: KeyClick {
        KeyClick { [recorder, feedback] in
            if !recorder.state.recording { feedback.key() }
        }
    }
}
