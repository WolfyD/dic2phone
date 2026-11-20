import AVFoundation
import Observation

/// The single tape player. Lists play a tape straight away; the deck can also hold a loaded tape
/// that keeps its place between play and pause, and can be scrubbed and skipped through.
/// With PLAY WITH EFFECTS on, plain tapes play through their effect copy.
@MainActor
@Observable
final class Player {
    private static let tickInterval: Duration = .milliseconds(100)
    /// Near enough to the end to count as played through, so PLAY starts over instead of
    /// playing the last fraction of a second.
    private static let endMarginMs: Int64 = 300
    private static let seekEndMarginMs: Int64 = 200

    private(set) var playingID: TapeID?
    private(set) var positionMs: Int64 = 0
    /// The tape in the deck.
    private(set) var loadedID: TapeID?
    private(set) var deckPositionMs: Int64 = 0

    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private let store: TapeStore
    @ObservationIgnored private let library: TapeLibrary
    @ObservationIgnored private let feedback: Feedback
    @ObservationIgnored private let audioSession: AudioSession
    @ObservationIgnored private var player: AVPlayer?
    /// Feeds a vault tape to the player; kept here because its item only holds it weakly.
    @ObservationIgnored private var sealedLoader: SealedAssetLoader?
    @ObservationIgnored private let silences = SilenceSkipper()
    @ObservationIgnored private var playingDurationMs: Int64 = 0
    @ObservationIgnored private var tick: Task<Void, Never>?
    @ObservationIgnored private var effectsSwitch: Task<Void, Never>?

    init(settings: Settings, store: TapeStore, library: TapeLibrary, feedback: Feedback, audioSession: AudioSession) {
        self.settings = settings
        self.store = store
        self.library = library
        self.feedback = feedback
        self.audioSession = audioSession
        loadedID = settings.deckTape
    }

    /// Looked up in the library each time, so a new title shows at once and a deleted tape
    /// leaves the deck empty.
    var loaded: Tape? {
        loadedID.flatMap(library.tape)
    }

    var deckPlaying: Bool {
        loadedID != nil && loadedID == playingID
    }

    func toggle(_ tape: Tape) {
        if playingID == tape.id {
            stop()
        } else {
            play(tape, fromMs: 0)
        }
    }

    /// Plays `tape` from `ms`; if it's already playing, just jumps there.
    func play(_ tape: Tape, fromMs ms: Int64) {
        if playingID == tape.id, let player {
            player.seek(to: Self.time(ms), toleranceBefore: .zero, toleranceAfter: .zero)
            setPosition(ms, of: tape.id)
            return
        }
        stop()
        let effectCopy = readyEffectCopy(of: tape)
        guard let item = effectCopy.map(AVPlayerItem.init(url:)) ?? makeItem(for: tape),
              (try? audioSession.activate()) != nil else { return }
        item.audioTimePitchAlgorithm = pitchAlgorithm
        let started = AVPlayer(playerItem: item)
        if ms > 0 {
            started.seek(to: Self.time(ms), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        started.playImmediately(atRate: settings.playSpeed)
        player = started
        playingID = tape.id
        playingDurationMs = tape.durationMs
        setPosition(ms, of: tape.id)
        if tape.isNew { library.markHeard([tape]) }
        startTicking()
        prepareSkipping()
        if let effectCopy {
            library.markEffectCopyPlayed(effectCopy)
        } else {
            switchToEffectsWhenMade(tape)
        }
    }

    func stop() {
        tick?.cancel()
        tick = nil
        effectsSwitch?.cancel()
        effectsSwitch = nil
        silences.stop()
        if let player, let playingID {
            setPosition(Self.milliseconds(player.currentTime()), of: playingID)
            player.pause()
        }
        player = nil
        sealedLoader = nil
        playingID = nil
        positionMs = 0
    }

    /// The speed or pitch setting changed: applies it to what's playing now.
    func applySpeed() {
        guard let player else { return }
        player.currentItem?.audioTimePitchAlgorithm = pitchAlgorithm
        player.rate = settings.playSpeed
    }

    /// Finds the silences on the tape playing, when SKIP SILENCE is on or has just been
    /// turned on.
    func prepareSkipping() {
        guard settings.skipSilence, let playingID, let tape = library.tape(playingID),
              let source = library.source(of: tape) else { return }
        silences.prepare(tape, from: source)
    }

    /// Starts making the deck tape's effect copy, if tapes play through the effects, so it's
    /// ready by the time PLAY is pressed.
    func prepareEffects() {
        guard let effects = settings.playingEffects, let tape = loaded else { return }
        Task { [library] in _ = await library.effectCopy(of: tape, with: effects) }
    }

    func load(_ tape: Tape) {
        guard loadedID != tape.id else { return }
        if playingID != nil { stop() }
        feedback.doorClose()
        loadedID = tape.id
        deckPositionMs = 0
        // A vault tape's name would give away when it was recorded, so it isn't written down.
        settings.deckTape = tape.rack == .vault ? nil : tape.id
        prepareEffects()
    }

    func eject() {
        if deckPlaying { stop() }
        feedback.doorOpen()
        loadedID = nil
        deckPositionMs = 0
        settings.deckTape = nil
    }

    /// Tapes moving into, out of or within the vault: they're stopped and taken out of the deck,
    /// so nothing keeps playing a vault tape once it's locked, or a file that has moved.
    func letGo(of tapes: [Tape]) {
        let ids = Set(tapes.map(\.id))
        silences.forget(ids)
        if let playingID, ids.contains(playingID) { stop() }
        guard let loadedID, ids.contains(loadedID) else { return }
        self.loadedID = nil
        deckPositionMs = 0
        settings.deckTape = nil
    }

    func playPause() {
        guard let tape = loaded else { return }
        if deckPlaying {
            stop()
        } else {
            let nearEnd = tape.durationMs > 0 && deckPositionMs >= tape.durationMs - Self.endMarginMs
            play(tape, fromMs: nearEnd ? 0 : deckPositionMs)
        }
    }

    /// Plays the deck's tape on from where it is, unless it's at the end.
    func playOn() {
        guard let tape = loaded, !deckPlaying, deckPositionMs < tape.durationMs - Self.endMarginMs else { return }
        play(tape, fromMs: deckPositionMs)
    }

    func seek(toMs ms: Int64) {
        guard let tape = loaded else { return }
        let clamped = min(max(ms, 0), max(tape.durationMs - Self.seekEndMarginMs, 0))
        if deckPlaying {
            play(tape, fromMs: clamped)
        } else {
            deckPositionMs = clamped
        }
    }

    /// A tap on a flag in the strip: the deck drops into it with a felt click.
    func jump(toFlag ms: Int64) {
        feedback.detent()
        seek(toMs: ms)
    }

    func skip(byMs deltaMs: Int64) {
        seek(toMs: deckPositionMs + deltaMs)
    }

    private func makeItem(for tape: Tape) -> AVPlayerItem? {
        guard tape.rack == .vault else { return AVPlayerItem(url: store.url(of: tape)) }
        guard let file = library.sealedFile(of: tape) else { return nil }
        let loader = SealedAssetLoader(file: file)
        sealedLoader = loader
        return loader.makeItem()
    }

    private func readyEffectCopy(of tape: Tape) -> URL? {
        settings.playingEffects.flatMap { library.readyEffectCopy(of: tape, with: $0) }
    }

    /// The tape plays as recorded while its effect copy is made, rather than keeping PLAY
    /// waiting, then carries on from the same place through the copy.
    private func switchToEffectsWhenMade(_ tape: Tape) {
        guard let effects = settings.playingEffects, tape.rack != .vault else { return }
        effectsSwitch = Task { [weak self, library] in
            guard let copy = await library.effectCopy(of: tape, with: effects), !Task.isCancelled else { return }
            self?.switchToEffectCopy(copy, of: tape.id)
        }
    }

    private func switchToEffectCopy(_ copy: URL, of id: TapeID) {
        guard playingID == id, let player else { return }
        let now = player.currentTime()
        let item = AVPlayerItem(url: copy)
        item.audioTimePitchAlgorithm = pitchAlgorithm
        player.replaceCurrentItem(with: item)
        player.seek(to: now, toleranceBefore: .zero, toleranceAfter: .zero)
        player.playImmediately(atRate: settings.playSpeed)
        library.markEffectCopyPlayed(copy)
    }

    private var pitchAlgorithm: AVAudioTimePitchAlgorithm {
        settings.tapePitch ? .varispeed : .timeDomain
    }

    private func setPosition(_ ms: Int64, of id: TapeID) {
        positionMs = ms
        if loadedID == id { deckPositionMs = ms }
    }

    private func startTicking() {
        tick = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                self?.update()
            }
        }
    }

    /// Follows the playhead. AVPlayer pauses by itself at the end of the tape, or when a call
    /// takes the audio away; either way the deck stops.
    private func update() {
        guard let player, let playingID else { return }
        setPosition(Self.milliseconds(player.currentTime()), of: playingID)
        skipSilence(in: player, of: playingID)
        guard player.timeControlStatus == .paused else { return }
        let ended = playingDurationMs > 0 && positionMs >= playingDurationMs - Self.endMarginMs
        let wasDeck = deckPlaying
        stop()
        if ended, wasDeck { deckPositionMs = 0 }
    }

    private func skipSilence(in player: AVPlayer, of id: TapeID) {
        guard settings.skipSilence, player.timeControlStatus == .playing,
              let to = silences.jump(fromMs: positionMs) else { return }
        player.seek(to: Self.time(to), toleranceBefore: .zero, toleranceAfter: .zero)
        setPosition(to, of: id)
    }

    private static func time(_ ms: Int64) -> CMTime {
        CMTime(value: ms, timescale: 1000)
    }

    private static func milliseconds(_ time: CMTime) -> Int64 {
        time.isNumeric ? Int64(time.seconds * 1000) : 0
    }
}
