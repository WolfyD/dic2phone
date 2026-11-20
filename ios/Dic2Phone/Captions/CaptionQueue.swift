import Foundation
import Observation

/// Makes captions one job at a time, in the order they were asked for, and tells the screens
/// how it's going. Work happens only while the app runs; iOS has no way to keep it going for
/// long in the background.
@MainActor
@Observable
final class CaptionQueue {
    private(set) var status: CaptionStatus?
    private(set) var lastError: String?
    private var jobs: [CaptionJob] = []
    private var current: CaptionJob?

    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private let library: TapeLibrary
    @ObservationIgnored private let models: ModelStore
    @ObservationIgnored private var finishedJobs = 0
    @ObservationIgnored private var worker: Task<Void, Never>?
    /// Changes with every cancel, so a cancelled run that is still winding down can tell it
    /// no longer owns the queue.
    @ObservationIgnored private var run = 0

    init(settings: Settings, library: TapeLibrary, models: ModelStore) {
        self.settings = settings
        self.library = library
        self.models = models
    }

    var isBusy: Bool { current != nil || !jobs.isEmpty }

    /// Tapes waiting for captions or getting them.
    var waitingTapes: Set<TapeID> { Set(allJobs.compactMap(\.tapeID)) }

    /// Models waiting to be downloaded from Setup, or downloading.
    var waitingModels: Set<SpeechModel> { Set(allJobs.compactMap(\.model)) }

    private var allJobs: [CaptionJob] { [current].compactMap { $0 } + jobs }

    func transcribe(_ tapes: [Tape]) {
        let waiting = waitingTapes
        let new = tapes.filter { !waiting.contains($0.id) }
        guard !new.isEmpty else { return }
        add(new.map(CaptionJob.caption))
    }

    func fetch(_ model: SpeechModel) {
        guard !models.isDownloaded(model), !waitingModels.contains(model) else { return }
        add([.fetch(model)])
    }

    func cancelAll() {
        run += 1
        worker?.cancel()
        worker = nil
        jobs = []
        current = nil
        finishedJobs = 0
        status = nil
    }

    /// The vault locked: its tapes leave the queue, and one being listened to is stopped, so
    /// nothing from inside goes on being read.
    func forgetVault() {
        jobs.removeAll(where: \.isVaultTape)
        guard current?.isVaultTape == true else { return }
        let rest = jobs
        cancelAll()
        add(rest)
    }

    private func add(_ new: [CaptionJob]) {
        guard !new.isEmpty else { return }
        lastError = nil
        jobs += new
        guard worker == nil else { return }
        let run = self.run
        worker = Task { await work(run) }
    }

    private func work(_ run: Int) async {
        var loaded: LoadedSpeechModel?
        while run == self.run, !jobs.isEmpty {
            current = jobs.removeFirst()
            if let job = current { await perform(job, run: run, loaded: &loaded) }
            guard run == self.run else { return }
            finishedJobs += 1
            current = nil
        }
        guard run == self.run else { return }
        worker = nil
        finishedJobs = 0
        status = nil
    }

    private func perform(_ job: CaptionJob, run: Int, loaded: inout LoadedSpeechModel?) async {
        do {
            switch job {
            case .caption(let tape): try await caption(tape, run: run, loaded: &loaded)
            case .fetch(let model): try await download(model, for: nil, run: run)
            }
        } catch is CancellationError {
            return
        } catch {
            guard run == self.run else { return }
            lastError = (error as? CaptionError ?? .transcriptionFailed).message
        }
    }

    private func caption(_ asked: Tape, run: Int, loaded: inout LoadedSpeechModel?) async throws {
        // The tape may have moved, or been deleted, since it was queued.
        guard let tape = library.tape(asked.id) else { return }
        let choice = settings.speechModel ?? .base
        if !models.isDownloaded(choice) {
            try await download(choice, for: tape.id, run: run)
        }
        let whisper = try await load(choice, for: tape.id, run: run, loaded: &loaded)
        guard let source = library.source(of: tape) else { throw CaptionError.vaultLocked }
        show(.listening, percent: 0, tape: tape.id, run: run)
        let transcriber = Transcriber(model: whisper, language: settings.captionLanguage)
        let cues = try await transcriber.cues(of: source, durationMs: tape.durationMs) { [weak self] percent in
            await self?.show(.listening, percent: percent, tape: tape.id, run: run)
        }
        guard run == self.run else { throw CancellationError() }
        try await library.saveTranscript(Transcript(cues: cues), for: tape)
    }

    private func download(_ model: SpeechModel, for tape: TapeID?, run: Int) async throws {
        show(.fetching(model), percent: 0, tape: tape, run: run)
        try await models.download(model) { [weak self] percent in
            await self?.show(.fetching(model), percent: percent, tape: tape, run: run)
        }
    }

    /// Keeps one model loaded for the whole run, since loading takes seconds.
    private func load(
        _ choice: SpeechModel,
        for tape: TapeID,
        run: Int,
        loaded: inout LoadedSpeechModel?
    ) async throws -> WhisperModel {
        if let loaded, loaded.choice == choice { return loaded.whisper }
        // Let go of the old model first: two may not fit in memory side by side.
        loaded = nil
        show(.loading, percent: 0, tape: tape, run: run)
        let url = models.url(of: choice)
        let whisper = try await Task.detached(priority: .userInitiated) { try WhisperModel(contentsOf: url) }.value
        loaded = LoadedSpeechModel(choice: choice, whisper: whisper)
        return whisper
    }

    private func show(_ step: CaptionStep, percent: Int, tape: TapeID?, run: Int) {
        guard run == self.run else { return }
        status = CaptionStatus(
            tape: tape,
            step: step,
            percent: percent,
            index: finishedJobs + 1,
            total: finishedJobs + jobs.count + 1
        )
    }
}
