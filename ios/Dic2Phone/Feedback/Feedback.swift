import AVFoundation

/// The deck's key sounds, the haptics that go with them, and the faint hiss while recording.
@MainActor
final class Feedback {
    /// The REC sound's length plus a margin: recording starts after it, so the click isn't on tape.
    static let recStartSoundLength: Duration = .milliseconds(340)

    private static let hissInHeadphones: Float = 0.7
    /// On the speaker, about a centimetre from the mic, the hiss has to stay below a quiet room's
    /// own noise. Measured on the Android app: 0.035 at 60 % volume. Scaling by the volume keeps
    /// the level in the room about the same at any volume setting.
    private static let hissOnSpeakerAtReferenceVolume: Float = 0.035
    private static let referenceVolume: Float = 0.6
    private static let hissFadeIn: TimeInterval = 0.4

    private let settings: Settings
    private let audioSession: AudioSession
    private let haptics: Haptics
    private var players: [DeckSound: AVAudioPlayer] = [:]
    private var hissPlayer: AVAudioPlayer?

    init(settings: Settings, audioSession: AudioSession, haptics: Haptics) {
        self.settings = settings
        self.audioSession = audioSession
        self.haptics = haptics
    }

    func recStart() {
        play(.recStart)
        haptics.play(.recStart)
    }

    /// Played once the mic is closed, so the clack isn't on the tape.
    func recStop() {
        play(.recStop)
        haptics.play(.recStop)
    }

    /// Felt, not heard: a sound would end up on the tape.
    func flag() {
        haptics.play(.flag)
    }

    /// Felt, not heard: a sound would end up on the tape.
    func latch() {
        haptics.play(.latch)
    }

    func key() {
        play(Bool.random() ? .softKey : .firmKey)
    }

    func detent() {
        play(.detent)
        haptics.play(.detent)
    }

    func doorOpen() {
        play(.eject)
        haptics.play(.doorOpen)
    }

    func doorClose() {
        play(.insert)
        haptics.play(.doorClose)
    }

    func startHiss() {
        guard hissPlayer == nil, settings.sounds, settings.hiss,
              let player = try? AVAudioPlayer(data: SynthSounds.hiss().wavData)
        else { return }
        player.numberOfLoops = -1
        player.volume = 0
        player.play()
        player.setVolume(hissVolume, fadeDuration: Self.hissFadeIn)
        hissPlayer = player
    }

    func stopHiss() {
        hissPlayer?.stop()
        hissPlayer = nil
    }

    private var hissVolume: Float {
        if audioSession.headphonesConnected { return Self.hissInHeadphones }
        let volume = audioSession.outputVolume
        guard volume > 0.01 else { return 0 }
        return min(Self.hissOnSpeakerAtReferenceVolume * Self.referenceVolume / volume, Self.hissInHeadphones)
    }

    private func play(_ sound: DeckSound) {
        guard settings.sounds, let player = player(for: sound) else { return }
        player.currentTime = 0
        player.play()
    }

    private func player(for sound: DeckSound) -> AVAudioPlayer? {
        if let player = players[sound] { return player }
        guard let player = try? AVAudioPlayer(data: sound.synthesize().wavData) else { return nil }
        player.volume = sound.volume
        player.prepareToPlay()
        players[sound] = player
        return player
    }
}
