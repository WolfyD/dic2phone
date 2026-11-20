import XCTest
@testable import Dic2Phone

final class NoiseGateTests: XCTestCase {
    private static let quietDb: Float = -70
    private static let loudDb: Float = -20
    private static let chunk = [Int16](repeating: 1_000, count: TapeFormat.chunkSize)
    /// Quiet chunks a rolling gate can hold before the pause counts as long.
    private static let chunksInMaxPause = NoiseGate.maxPause / TapeFormat.chunkSize

    func testPassesEverythingWhenNotGated() {
        var gate = NoiseGate(gated: false, sensitivity: 1)
        XCTAssertEqual(gate.feed(Self.chunk, rmsDb: Self.quietDb, tapeHasAudio: false), [Self.chunk])
        XCTAssertTrue(gate.rolling)
    }

    func testWritesNothingWhileQuiet() {
        var gate = NoiseGate(gated: true, sensitivity: 1)
        XCTAssertEqual(feedQuiet(&gate, chunks: 100), [])
        XCTAssertFalse(gate.rolling)
        XCTAssertGreaterThan(gate.skippedSamples, 0)
    }

    func testOpensOnSoundAndKeepsTheMomentBeforeIt() {
        var gate = NoiseGate(gated: true, sensitivity: 1)
        feedQuiet(&gate, chunks: 50, tapeHasAudio: false)
        XCTAssertEqual(feedLoud(&gate, tapeHasAudio: false), [], "A single loud chunk could be a click")
        let opened = feedLoud(&gate, tapeHasAudio: false)
        let written = opened.map(\.count).reduce(0, +)
        XCTAssertTrue(gate.rolling)
        XCTAssertGreaterThanOrEqual(written, NoiseGate.preRoll)
        XCTAssertLessThan(written, NoiseGate.preRoll + TapeFormat.chunkSize)
        XCTAssertEqual(gate.cuts, 0, "Starting the tape isn't a cut")
    }

    func testKeepsAShortPauseWhole() {
        var gate = openedGate()
        XCTAssertEqual(feedQuiet(&gate, chunks: 3), [])
        XCTAssertEqual(feedLoud(&gate).count, 4)
    }

    func testALongPauseLeavesAFadedTailAndCloses() {
        var gate = openedGate()
        XCTAssertEqual(feedQuiet(&gate, chunks: Self.chunksInMaxPause), [])
        let tail = feedQuiet(&gate, chunks: 1)
        XCTAssertFalse(gate.rolling)
        XCTAssertEqual(tail.count, 1)
        XCTAssertEqual(tail.first?.count, NoiseGate.tail)
        XCTAssertEqual(tail.first?.last, 0)
    }

    func testReopeningCountsACutAndFadesIn() {
        var gate = openedGate()
        feedQuiet(&gate, chunks: Self.chunksInMaxPause + 1)
        feedLoud(&gate)
        let reopened = feedLoud(&gate)
        XCTAssertEqual(gate.cuts, 1)
        XCTAssertEqual(reopened.first?.first, 0)
    }

    func testDrainTailKeepsAPauseInProgress() {
        var gate = openedGate()
        XCTAssertEqual(gate.drainTail(), [])
        feedQuiet(&gate, chunks: 3)
        let drained = gate.drainTail()
        XCTAssertEqual(drained.map(\.count), [3 * TapeFormat.chunkSize])
        XCTAssertEqual(drained.first?.last, 0)
    }

    func testFadesRampBetweenSilenceAndFullLevel() {
        let samples = [Int16](repeating: 10_000, count: NoiseGate.fadeLength * 2)
        let fadedIn = NoiseGate.faded(samples, out: false)
        XCTAssertEqual(fadedIn[0], 0)
        XCTAssertEqual(fadedIn[NoiseGate.fadeLength / 2], 5_000)
        XCTAssertEqual(fadedIn[NoiseGate.fadeLength], 10_000)
        let fadedOut = NoiseGate.faded(samples, out: true)
        XCTAssertEqual(fadedOut.first, 10_000)
        XCTAssertEqual(fadedOut.last, 0)
    }

    private func openedGate() -> NoiseGate {
        var gate = NoiseGate(gated: true, sensitivity: 1)
        feedQuiet(&gate, chunks: 50, tapeHasAudio: false)
        feedLoud(&gate, tapeHasAudio: false)
        feedLoud(&gate, tapeHasAudio: false)
        return gate
    }

    @discardableResult
    private func feedQuiet(_ gate: inout NoiseGate, chunks: Int, tapeHasAudio: Bool = true) -> [[Int16]] {
        (0..<chunks).flatMap { _ in gate.feed(Self.chunk, rmsDb: Self.quietDb, tapeHasAudio: tapeHasAudio) }
    }

    @discardableResult
    private func feedLoud(_ gate: inout NoiseGate, tapeHasAudio: Bool = true) -> [[Int16]] {
        gate.feed(Self.chunk, rmsDb: Self.loudDb, tapeHasAudio: tapeHasAudio)
    }
}
