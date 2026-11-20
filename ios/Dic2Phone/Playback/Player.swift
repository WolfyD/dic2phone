import AVFoundation
import Observation

/// The single tape player. Lists play a tape straight away; the deck can also hold a loaded tape
/// that keeps its place between play and pause, and can be scrubbed and skipped through.
@MainActor
@Observable
final class Player {
    private static let tickInterval: Duration = .milliseconds(100)
    /// Near enough to the end to count as played through, so PLAY starts over instead of
    /// playing the last fraction of a second.
    private static let endMarginMs: Int64 = 300
    private static let seekEndMarginMs: Int64 = 200
    private static let windStepMs: Int64 = 10_000
    private static let windRepeatDelay: Duration = .milliseconds(450)
    private static let windRepeatInterval: Duration = .milliseconds(160)

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
    @ObservationIgnored private var playingDurationMs: Int64 = 0
    @ObservationIgnored private var tick: Task<Void, Never>?
    @ObservationIgnored private var winding: Task<Void, Never>?

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
        guard let item = makeItem(for: tape), (try? audioSession.activate()) != nil else { return }
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
    }

    func stop() {
        tick?.cancel()
        tick = nil
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

    func load(_ tape: Tape) {
        guard loadedID != tape.id else { return }
        if playingID != nil { stop() }
        feedback.doorClose()
        loadedID = tape.id
        deckPositionMs = 0
        // A vault tape's name would give away when it was recorded, so it isn't written down.
        settings.deckTape = tape.rack == .vault ? nil : tape.id
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

    /// REW or FF pressed: winds ten seconds at once, then on and on for as long as it's held.
    func startWinding(forward: Bool) {
        let step = forward ? Self.windStepMs : -Self.windStepMs
        skip(byMs: step)
        winding?.cancel()
        winding = Task { [weak self] in
            try? await Task.sleep(for: Self.windRepeatDelay)
            while !Task.isCancelled {
                self?.skip(byMs: step)
                try? await Task.sleep(for: Self.windRepeatInterval)
            }
        }
    }

    func stopWinding() {
        winding?.cancel()
        winding = nil
    }

    private func makeItem(for tape: Tape) -> AVPlayerItem? {
        guard tape.rack == .vault else { return AVPlayerItem(url: store.url(of: tape)) }
        guard let file = library.sealedFile(of: tape) else { return nil }
        let loader = SealedAssetLoader(file: file)
        sealedLoader = loader
        return loader.makeItem()
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
        guard player.timeControlStatus == .paused else { return }
        let ended = playingDurationMs > 0 && positionMs >= playingDurationMs - Self.endMarginMs
        let wasDeck = deckPlaying
        stop()
        if ended, wasDeck { deckPositionMs = 0 }
    }

    private static func time(_ ms: Int64) -> CMTime {
        CMTime(value: ms, timescale: 1000)
    }

    private static func milliseconds(_ time: CMTime) -> Int64 {
        time.isNumeric ? Int64(time.seconds * 1000) : 0
    }
}
