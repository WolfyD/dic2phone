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
    let locator: Locator
    let micChooser: MicChooser

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
        let library = TapeLibrary(
            store: store, vaultStore: vaultStore,
            heard: HeardList(defaults: defaults), effectCopies: EffectCopies(storage: storage)
        )
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
        let locator = Locator()
        self.locator = locator
        micChooser = MicChooser(settings: settings, audioSession: audioSession)
        recorder = Recorder(
            settings: settings, store: store, library: library, feedback: feedback,
            audioSession: audioSession, player: player, newTapeCaptions: newTapeCaptions,
            locator: locator, makeMic: { EngineMic() }
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
        await tidyTapes()
        player.prepareEffects()
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
    /// change, tapes recorded in a locked phone can now be read, and days pass for AUTO-TIDY.
    func appBecameActive() {
        vault.checkPasscode()
        newTapeCaptions.appBecameActive()
        Task {
            await library.reload()
            await tidyTapes()
        }
    }

    /// AUTO-TIDY, and effect copies not played for a while. Never mid-recording, when the deck
    /// is busy with the tape being made.
    private func tidyTapes() async {
        guard !recorder.state.recording else { return }
        let overdue = AutoTidy(settings: settings, player: player).overdue(in: library.deck, now: .now)
        if !overdue.isEmpty {
            _ = await library.delete(overdue)
        }
        await library.tidyEffectCopies(unplayedDays: settings.effectKeepDays)
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
