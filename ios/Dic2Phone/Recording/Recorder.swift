import Foundation
import Observation

/// Starts and stops recording sessions, and writes down what each tape recorded.
@MainActor
@Observable
final class Recorder {
    private static let minTapeMs: Int64 = 700
    /// A tape this long whose loudest sample is this quiet is digital silence: another app is
    /// holding the mic, or a privacy toggle blocks it.
    private static let silentAfterMs: Int64 = 2000
    private static let silentPeak = 8
    /// A press of REC shorter than this is a tap: it locks recording on.
    private static let latchTapLimit: Duration = .milliseconds(350)

    private(set) var state = RecorderState()

    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private let store: TapeStore
    @ObservationIgnored private let library: TapeLibrary
    @ObservationIgnored private let feedback: Feedback
    @ObservationIgnored private let audioSession: AudioSession
    @ObservationIgnored private let player: Player
    @ObservationIgnored private let newTapeCaptions: NewTapeCaptions
    @ObservationIgnored private let makeMic: () -> any MicInput
    @ObservationIgnored private var session: RecordingSession?
    @ObservationIgnored private var keyPressedAt: ContinuousClock.Instant?

    init(
        settings: Settings,
        store: TapeStore,
        library: TapeLibrary,
        feedback: Feedback,
        audioSession: AudioSession,
        player: Player,
        newTapeCaptions: NewTapeCaptions,
        makeMic: @escaping () -> any MicInput
    ) {
        self.settings = settings
        self.store = store
        self.library = library
        self.feedback = feedback
        self.audioSession = audioSession
        self.player = player
        self.newTapeCaptions = newTapeCaptions
        self.makeMic = makeMic
    }

    /// REC pressed: records while it's held, or stops a recording that's already running.
    func keyDown() {
        if state.recording {
            keyPressedAt = nil
            stop()
        } else {
            keyPressedAt = .now
            start(source: "rec-key", latched: false)
        }
    }

    /// REC let go: after a quick tap it keeps recording; after a hold it stops.
    func keyUp() {
        guard let pressedAt = keyPressedAt else { return }
        keyPressedAt = nil
        if ContinuousClock.now - pressedAt < Self.latchTapLimit {
            latch()
        } else {
            stop()
        }
    }

    /// - Parameters:
    ///   - source: what started it, kept in the tape's metadata.
    ///   - latched: start locked on, instead of recording only while REC is held.
    func start(source: String, latched: Bool) {
        guard session == nil, micAllowed() else { return }
        player.stop()
        let session = RecordingSession(source: source, latched: latched)
        self.session = session
        feedback.recStart()
        let vox = latched && settings.vox
        state = RecorderState(recording: true, startedAt: .now, latched: latched, vox: vox, rolling: !vox)
        if latched { feedback.latch() }
        session.startTask = Task {
            try? await Task.sleep(for: Feedback.recStartSoundLength)
            guard !Task.isCancelled else { return }
            beginTape(session)
        }
    }

    /// Keeps recording after REC is let go.
    func latch() {
        guard let session, !session.latched else { return }
        let vox = settings.vox
        session.latched = true
        session.gated = vox
        if let engine = session.engine {
            Task { await engine.setGated(vox) }
        }
        state.latched = true
        state.vox = vox
        feedback.latch()
    }

    func flag() {
        guard let session, let engine = session.engine else { return }
        Task { await handle(engine.flag(), from: session) }
    }

    func stop() {
        guard let session else { return }
        self.session = nil
        session.startTask?.cancel()
        feedback.stopHiss()
        state = RecorderState()
        guard let engine = session.engine else {
            feedback.recStop()
            return
        }
        Task { await close(session, engine: engine) }
    }

    private func micAllowed() -> Bool {
        switch audioSession.micPermission {
        case .granted:
            return true
        case .undetermined:
            Task { _ = await audioSession.requestMicPermission() }
            return false
        default:
            state.error = String(localized: "Microphone access is off. Turn it on in Settings › Dic2Phone.")
            return false
        }
    }

    private func beginTape(_ session: RecordingSession) {
        guard isCurrent(session) else { return }
        let mic = makeMic()
        let chunks: AsyncStream<[Int16]>
        do {
            try audioSession.activate()
            chunks = try mic.start()
        } catch {
            stop()
            state.error = String(localized: "Microphone unavailable")
            return
        }
        session.gated = session.latched && settings.vox
        let engine = TapeEngine(
            storage: store.storage,
            gated: session.gated,
            detectsSnaps: settings.snapToFlag,
            voxSensitivity: settings.voxSensitivity,
            maxTapeMs: settings.maxTapeMs,
            makeSink: { try AssetTapeWriter(url: $0) }
        )
        session.mic = mic
        session.engine = engine
        session.feedTask = Task { await record(chunks, with: engine, for: session) }
        feedback.startHiss()
    }

    private func record(_ chunks: AsyncStream<[Int16]>, with engine: TapeEngine, for session: RecordingSession) async {
        await handle(engine.start(), from: session)
        for await chunk in chunks {
            await handle(engine.feed(chunk), from: session)
        }
        // The mic went away by itself (a headset unplugged): close the tape properly.
        if isCurrent(session) { stop() }
    }

    /// The engine ignores chunks from the moment STOP is pressed (they may hold its click),
    /// the mic is shut, and only once every chunk already sent is through does the tape close.
    private func close(_ session: RecordingSession, engine: TapeEngine) async {
        await engine.stop()
        session.mic?.stop()
        await session.feedTask?.value
        await handle(engine.close(), from: session)
        feedback.recStop()
        newTapeCaptions.recorded(session.keptTapes)
        if self.session == nil, let message = closingMessage(for: session) {
            state.error = message
        }
    }

    private func closingMessage(for session: RecordingSession) -> String? {
        if session.failed { return String(localized: "Recording failed") }
        if session.silent { return String(localized: "Last tape is silent. Is the mic blocked or in use by another app?") }
        if session.keptTapes.isEmpty, session.gated { return String(localized: "No sound heard, so nothing was recorded") }
        return nil
    }

    private func handle(_ events: [TapeEvent], from session: RecordingSession) async {
        for event in events {
            switch event {
            case .tapeStarted(let part):
                guard isCurrent(session) else { continue }
                state.part = part
                state.flags = 0
            case .flagged(let count):
                feedback.flag()
                guard isCurrent(session) else { continue }
                state.flags = count
            case .meter(let meter):
                guard isCurrent(session) else { continue }
                state.level = meter.level
                state.rolling = meter.rolling
                state.tapeMs = meter.tapeMs
                state.vox = meter.vox
            case .tapeFinished(let tape):
                await save(tape, from: session)
            case .failed:
                session.failed = true
                if isCurrent(session) { stop() }
            }
        }
    }

    private func save(_ tape: FinishedTape, from session: RecordingSession) async {
        guard tape.written, tape.durationMs >= Self.minTapeMs else {
            await store.discardRecording(tape.id)
            return
        }
        if tape.durationMs > Self.silentAfterMs, tape.peak < Self.silentPeak { session.silent = true }
        do {
            try await store.keepRecording(tape.id, meta: meta(for: tape, in: session))
        } catch {
            // Left in the recording folder, where the next launch rescues it.
            session.failed = true
            return
        }
        // The first hour of a long session only now turns out to be part 1.
        if tape.part == 2, let first = session.keptTapes.first {
            try? await store.updateMeta(of: first) { $0.part = 1 }
        }
        session.keptTapes.append(tape.id)
        await library.reload()
    }

    private func meta(for tape: FinishedTape, in session: RecordingSession) -> TapeMeta {
        var meta = TapeMeta()
        meta.startedAtMs = Self.epochMs(tape.startedAt)
        meta.endedAtMs = Self.epochMs(tape.endedAt)
        meta.durationMs = tape.durationMs
        meta.format = TapeFormat.label
        meta.peakDb = Double(tape.peakDb)
        meta.averageDb = Double(tape.rmsDb)
        meta.source = tape.part > 1 ? "split" : session.source
        meta.device = DeviceLabel.current
        meta.latched = session.latched
        meta.vox = tape.vox
        meta.cuts = tape.cuts
        meta.skippedMs = tape.skippedMs
        meta.part = tape.part > 1 ? tape.part : 0
        meta.flags = tape.flags
        return meta
    }

    private func isCurrent(_ session: RecordingSession) -> Bool {
        self.session === session
    }

    private static func epochMs(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }
}
