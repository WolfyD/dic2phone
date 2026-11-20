import XCTest
@testable import Dic2Phone

final class TapeEngineTests: XCTestCase {
    private static let quiet = [Int16](repeating: 0, count: TapeFormat.chunkSize)
    private static let loud = [Int16](repeating: 16_000, count: TapeFormat.chunkSize)
    private static let chunkSamples = Int64(TapeFormat.chunkSize)

    private var root: URL!
    private var storage: Storage!
    private var factory: FakeSinkFactory!

    override func setUpWithError() throws {
        root = try URL.temporaryFolder()
        storage = try Storage.fixture(in: root)
        factory = FakeSinkFactory()
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testAnOpenTapeStartsAtOnceAndKeepsEverySample() async throws {
        let engine = makeEngine()
        let started = await engine.start()
        let fed = await feed(engine, Self.quiet, times: 3)
        let closed = await engine.close()

        XCTAssertEqual(started.compactMap(\.startedPart), [1])
        XCTAssertTrue(fed.compactMap(\.finishedTape).isEmpty)
        let tape = try XCTUnwrap(closed.compactMap(\.finishedTape).first)
        XCTAssertEqual(tape.part, 1)
        XCTAssertEqual(tape.samples, 3 * Self.chunkSamples)
        XCTAssertTrue(tape.written)
        XCTAssertEqual(factory.sinks.first?.sampleTimes, [0, Self.chunkSamples, 2 * Self.chunkSamples])
    }

    func testAFullTapeRollsOntoANewOne() async {
        // 50 ms is 2,205 samples: the third chunk fills the tape.
        let engine = makeEngine(maxTapeMs: 50)
        _ = await engine.start()
        var events = await feed(engine, Self.quiet, times: 4)
        events += await engine.close()

        let finished = events.compactMap(\.finishedTape)
        XCTAssertEqual(events.compactMap(\.startedPart), [2])
        XCTAssertEqual(finished.map(\.part), [1, 2])
        XCTAssertEqual(finished.map(\.samples), [3 * Self.chunkSamples, Self.chunkSamples])
        XCTAssertEqual(Set(finished.map(\.id)).count, 2)
    }

    func testFlagsLandAheadOfTheMomentAndAreSpacedApart() async throws {
        let engine = makeEngine()
        _ = await engine.start()
        let first = await engine.flag()
        let tooSoon = await engine.flag()
        _ = await feed(engine, Self.quiet, times: 130)
        let second = await engine.flag()
        let closed = await engine.close()

        XCTAssertEqual(first.compactMap(\.flagCount), [1])
        XCTAssertTrue(tooSoon.isEmpty)
        XCTAssertEqual(second.compactMap(\.flagCount), [2])
        let tape = try XCTUnwrap(closed.compactMap(\.finishedTape).first)
        let secondFlagMs = TapeFormat.milliseconds(ofSamples: 130 * Self.chunkSamples) - TapeEngine.flagLeadMs
        XCTAssertEqual(tape.flags, [0, secondFlagMs])
        XCTAssertEqual(RescueNote.read(from: storage.rescueNoteURL(tape.id))?.flags, tape.flags)
    }

    func testANoiseActivatedTapeWaitsForSound() async {
        let engine = makeEngine(gated: true)
        let started = await engine.start()
        let whileQuiet = await feed(engine, Self.quiet, times: 20)
        let onSound = await feed(engine, Self.loud, times: 2)

        XCTAssertTrue(started.isEmpty)
        XCTAssertTrue(whileQuiet.compactMap(\.startedPart).isEmpty)
        XCTAssertEqual(onSound.compactMap(\.startedPart), [1])
    }

    func testReportsTheMeterEveryFourChunks() async throws {
        let engine = makeEngine()
        _ = await engine.start()
        let meters = await feed(engine, Self.loud, times: 4).compactMap(\.meter)

        let meter = try XCTUnwrap(meters.first)
        XCTAssertEqual(meters.count, 1)
        XCTAssertTrue(meter.rolling)
        XCTAssertFalse(meter.vox)
        XCTAssertEqual(meter.tapeMs, TapeFormat.milliseconds(ofSamples: 4 * Self.chunkSamples))
        XCTAssertGreaterThan(meter.level, 0.8)
    }

    func testIgnoresWhatComesAfterStop() async {
        let engine = makeEngine()
        _ = await engine.start()
        _ = await engine.feed(Self.quiet)
        await engine.stop()
        let afterStop = await engine.feed(Self.quiet)
        let closed = await engine.close()

        XCTAssertTrue(afterStop.isEmpty)
        XCTAssertEqual(closed.compactMap(\.finishedTape).first?.samples, Self.chunkSamples)
    }

    func testAFailedWriteIsReportedOnceAndEndsTheRecording() async {
        factory = FakeSinkFactory(failsOnAppend: true)
        let engine = makeEngine()
        _ = await engine.start()
        let first = await engine.feed(Self.quiet)
        let later = await engine.feed(Self.quiet)

        XCTAssertEqual(first.filter(\.isFailure).count, 1)
        XCTAssertTrue(later.isEmpty)
    }

    func testATapeThatCantBeOpenedIsAFailure() async {
        factory = FakeSinkFactory(refusesToOpen: true)
        let started = await makeEngine().start()

        XCTAssertEqual(started.filter(\.isFailure).count, 1)
        XCTAssertTrue(started.compactMap(\.startedPart).isEmpty)
    }

    private func makeEngine(gated: Bool = false, maxTapeMs: Int64 = 3_600_000) -> TapeEngine {
        let sinks: FakeSinkFactory = self.factory
        return TapeEngine(
            storage: storage,
            gated: gated,
            detectsSnaps: false,
            voxSensitivity: 1,
            maxTapeMs: maxTapeMs,
            makeSink: { try sinks.makeSink(at: $0) }
        )
    }

    private func feed(_ engine: TapeEngine, _ chunk: [Int16], times: Int) async -> [TapeEvent] {
        var events: [TapeEvent] = []
        for _ in 0..<times {
            events += await engine.feed(chunk)
        }
        return events
    }
}
