import AVFoundation

/// Builds the app's services once, wired to each other, and runs the work that belongs to the
/// app rather than to a screen: saving cut-off tapes and clearing unsealed copies at launch,
/// and stopping for phone calls.
@MainActor
final class AppModel {
    let settings: Settings
    let library: TapeLibrary
    let feedback: Feedback
    let player: Player
    let winder: DeckWinder
    let recorder: Recorder
    let flagKey: FlagKey
    let vault: Vault
    let captions: CaptionQueue

    private let newTapeCaptions: NewTapeCaptions
    private let audioSession: AudioSession
    private let vaultStore: VaultStore
    private let rescue: TapeRescue
    private let leftovers: [TapeID]

    init() throws {
        let storage = try Storage.standard()
        try storage.prepare()
        let defaults = UserDefaults.standard
        let store = TapeStore(storage: storage)
        let vaultStore = VaultStore(storage: storage, tapeStore: store)
        let audioSession = AudioSession()
        let settings = Settings(defaults: defaults)
        let library = TapeLibrary(store: store, vaultStore: vaultStore, heard: HeardList(defaults: defaults))
        let feedback = Feedback(settings: settings, audioSession: audioSession, haptics: Haptics())
        let player = Player(settings: settings, store: store, library: library, feedback: feedback, audioSession: audioSession)
        // Ephemeral: nothing about the download is kept in a cache or cookie store.
        let models = ModelStore(storage: storage, session: URLSession(configuration: .ephemeral))
        let captions = CaptionQueue(settings: settings, library: library, models: models)
        let newTapeCaptions = NewTapeCaptions(settings: settings, library: library, queue: captions)
        self.settings = settings
        self.library = library
        self.feedback = feedback
        self.player = player
        winder = DeckWinder(
            player: player, settings: settings, feedback: feedback,
            library: library, cue: CuePlayer(audioSession: audioSession)
        )
        self.audioSession = audioSession
        self.vaultStore = vaultStore
        self.captions = captions
        self.newTapeCaptions = newTapeCaptions
        recorder = Recorder(
            settings: settings, store: store, library: library, feedback: feedback,
            audioSession: audioSession, player: player, newTapeCaptions: newTapeCaptions,
            makeMic: { EngineMic() }
        )
        flagKey = FlagKey(player: player, library: library)
        vault = Vault(keychain: VaultKeychain(), store: vaultStore, library: library, player: player, captions: captions)
        rescue = TapeRescue(store: store, device: DeviceLabel.current)
        leftovers = rescue.leftovers()
    }

    func start() async {
        // If this fails, activating the session to record or play fails too, and says so there.
        try? audioSession.configure()
        _ = await rescue.rescue(leftovers)
        await vaultStore.clearUnsealed()
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

    /// Tapes can arrive or leave through the Files app while Dic2Phone is away, the passcode can
    /// change, and tapes recorded in a locked phone can now be read.
    func appBecameActive() {
        vault.checkPasscode()
        newTapeCaptions.appBecameActive()
        Task { await library.reload() }
    }

    /// Clicks are silent while recording: they would end up on the tape.
    var keyClick: KeyClick {
        KeyClick { [recorder, feedback] in
            if !recorder.state.recording { feedback.key() }
        }
    }

    var detentClick: KeyClick {
        KeyClick { [feedback] in feedback.detent() }
    }
}
