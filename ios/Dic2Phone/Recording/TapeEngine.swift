import Foundation

/// The tape transport: listens to the microphone's chunks (VU level, finger snaps, the noise
/// gate) and writes them to tapes, rolling onto a new tape when one is full.
///
/// Tape time is counted in samples written, so silences skipped by the gate don't exist on
/// the tape. Every call returns the events it caused, in order.
actor TapeEngine {
    /// Flags land this far before the moment they were made, so jumping to one gives a lead-in.
    static let flagLeadMs: Int64 = 1500
    private static let flagSpacingMs: Int64 = 1000
    private static let chunksPerMeterReading = 4

    private let storage: Storage
    private let makeSink: @Sendable (URL) throws -> any TapeSink
    private let detectsSnaps: Bool
    private let maxTapeSamples: Int64
    private var gate: NoiseGate
    private var snapDetector = SnapDetector()
    private var tape: OpenTape?
    private var part = 0
    private var flags: [Int64] = []
    private var stopped = false
    private var failed = false
    private var chunksSinceMeter = 0
    private var meterPeak = 0
    private var events: [TapeEvent] = []

    init(
        storage: Storage,
        gated: Bool,
        detectsSnaps: Bool,
        voxSensitivity: Int,
        maxTapeMs: Int64,
        makeSink: @escaping @Sendable (URL) throws -> any TapeSink
    ) {
        self.storage = storage
        self.detectsSnaps = detectsSnaps
        self.maxTapeSamples = maxTapeMs * Int64(TapeFormat.sampleRate) / 1000
        self.gate = NoiseGate(gated: gated, sensitivity: voxSensitivity)
        self.makeSink = makeSink
    }

    func start() -> [TapeEvent] {
        if !gate.gated, !stopped { _ = openTape() }
        return takeEvents()
    }

    func feed(_ chunk: [Int16]) async -> [TapeEvent] {
        guard !stopped, !failed else { return [] }
        let level = ChunkLevel(chunk)
        meterPeak = max(meterPeak, level.peak)
        if detectsSnaps, snapDetector.feed(chunk) { addFlag() }
        let writes = gate.feed(chunk, rmsDb: level.rmsDb, tapeHasAudio: (tape?.samples ?? 0) > 0)
        for chunkToWrite in writes { await write(chunkToWrite) }
        chunksSinceMeter += 1
        if chunksSinceMeter == Self.chunksPerMeterReading, !stopped {
            chunksSinceMeter = 0
            events.append(.meter(meterReading()))
        }
        return takeEvents()
    }

    func flag() -> [TapeEvent] {
        addFlag()
        return takeEvents()
    }

    /// Switches noise activation on or off mid-session, as when REC is latched.
    func setGated(_ gated: Bool) {
        gate.gated = gated
    }

    /// Ignores everything fed from now on: those chunks may already hold the STOP click.
    func stop() {
        stopped = true
    }

    /// Keeps the natural tail of any pause being held back, then closes the tape.
    func close() async -> [TapeEvent] {
        stopped = true
        if tape != nil {
            for chunkToWrite in gate.drainTail() { await write(chunkToWrite) }
        }
        await finishTape()
        return takeEvents()
    }

    private func takeEvents() -> [TapeEvent] {
        defer { events.removeAll() }
        return events
    }

    private var positionMs: Int64 {
        TapeFormat.milliseconds(ofSamples: (tape?.samples ?? 0) + Int64(gate.pendingCount))
    }

    private func meterReading() -> TapeMeter {
        let peakDb = ChunkLevel.peakDecibels(meterPeak)
        meterPeak = 0
        return TapeMeter(
            level: min(max((peakDb + 48) / 48, 0), 1),
            rolling: gate.rolling || !gate.gated,
            tapeMs: positionMs,
            vox: gate.gated
        )
    }

    private func addFlag() {
        let at = max(positionMs - Self.flagLeadMs, 0)
        if let last = flags.last, at - last < Self.flagSpacingMs { return }
        flags.append(at)
        writeRescueNote()
        events.append(.flagged(count: flags.count))
    }

    private func openTape() -> OpenTape? {
        if let tape { return tape }
        let id = storage.unusedTapeID(startedAt: .now)
        do {
            let sink = try makeSink(storage.recordingURL(id))
            part += 1
            let opened = OpenTape(id: id, part: part, startedAt: .now, sink: sink)
            tape = opened
            writeRescueNote()
            events.append(.tapeStarted(part: part))
            return opened
        } catch {
            fail()
            return nil
        }
    }

    private func write(_ chunk: [Int16]) async {
        guard !chunk.isEmpty, !failed, let current = openTape() else { return }
        do {
            try await current.append(chunk)
        } catch {
            fail()
            return
        }
        if current.samples >= maxTapeSamples { await finishTape() }
    }

    private func finishTape() async {
        guard let finishing = tape else { return }
        tape = nil
        let written = await finishing.sink.finish()
        events.append(.tapeFinished(FinishedTape(
            id: finishing.id,
            written: written,
            part: finishing.part,
            samples: finishing.samples,
            peak: finishing.peak,
            rmsDb: finishing.rmsDb,
            flags: flags,
            vox: gate.gated || gate.cuts > 0,
            cuts: gate.cuts,
            skippedMs: TapeFormat.milliseconds(ofSamples: Int64(gate.skippedSamples)),
            startedAt: finishing.startedAt,
            endedAt: .now
        )))
        flags = []
        gate.resetCounters()
    }

    private func writeRescueNote() {
        guard let tape else { return }
        let note = RescueNote(
            startedAtMs: Int64(tape.startedAt.timeIntervalSince1970 * 1000),
            vox: gate.gated || gate.cuts > 0,
            flags: flags
        )
        try? note.write(to: storage.rescueNoteURL(tape.id))
    }

    private func fail() {
        guard !failed else { return }
        failed = true
        events.append(.failed)
    }
}
