import XCTest
@testable import Dic2Phone

final class TapeProcessorTests: XCTestCase {
    private static let sampleRate = 44_100.0
    private static let noEffects = TapeEffects(hiss: false, muffle: false, wow: false, saturate: false)

    func testEachEffectHasItsOwnBitInTheMask() {
        XCTAssertEqual(TapeEffects().mask, 15)
        XCTAssertEqual(TapeEffects(hiss: true, muffle: false, wow: true, saturate: false).mask, 5)
        XCTAssertEqual(Self.noEffects.mask, 0)
        XCTAssertFalse(Self.noEffects.any)
    }

    func testWithNoEffectsTheSoundPassesUntouched() {
        var processor = TapeProcessor(effects: Self.noEffects, sampleRate: Self.sampleRate)
        let tone = Self.tone(seconds: 0.1)
        var samples = tone
        processor.process(&samples)
        XCTAssertEqual(samples, tone)
    }

    func testSaturationSquashesPeaksAndLiftsQuietBits() {
        XCTAssertEqual(TapeProcessor.saturated(0), 0)
        XCTAssertEqual(TapeProcessor.saturated(1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(TapeProcessor.saturated(-4), -0.5, accuracy: 0.0001)
        XCTAssertEqual(TapeProcessor.saturated(0.01), 0.015, accuracy: 0.0005)
    }

    func testHissIsFaintButThere() {
        var processor = TapeProcessor(
            effects: TapeEffects(hiss: true, muffle: false, wow: false, saturate: false),
            sampleRate: Self.sampleRate
        )
        var silence = [Float](repeating: 0, count: Int(Self.sampleRate))
        processor.process(&silence)
        let loudest = silence.map(abs).max() ?? 0
        XCTAssertGreaterThan(loudest, 0.001)
        XCTAssertLessThan(loudest, 0.05)
    }

    func testWowDelaysTheSoundByAboutSixMilliseconds() {
        var processor = TapeProcessor(
            effects: TapeEffects(hiss: false, muffle: false, wow: true, saturate: false),
            sampleRate: Self.sampleRate
        )
        var step = [Float](repeating: 1, count: 1000)
        processor.process(&step)
        let firstHeard = step.firstIndex { $0 > 0.5 } ?? -1
        XCTAssertEqual(Double(firstHeard) / Self.sampleRate, 0.006, accuracy: 0.0015)
    }

    func testTheSameTapeComesOutTheSameEveryTime() {
        func render() -> [Float] {
            var processor = TapeProcessor(effects: TapeEffects(), sampleRate: Self.sampleRate)
            var samples = Self.tone(seconds: 0.5)
            processor.process(&samples)
            return samples
        }
        XCTAssertEqual(render(), render())
    }

    func testRunsCarryOnFromEachOther() {
        var whole = TapeProcessor(effects: TapeEffects(), sampleRate: Self.sampleRate)
        var inOneGo = Self.tone(seconds: 0.2)
        whole.process(&inOneGo)

        var pieces = TapeProcessor(effects: TapeEffects(), sampleRate: Self.sampleRate)
        let tone = Self.tone(seconds: 0.2)
        var first = Array(tone[..<3000])
        var second = Array(tone[3000...])
        pieces.process(&first)
        pieces.process(&second)
        XCTAssertEqual(first + second, inOneGo)
    }

    private static func tone(seconds: Double) -> [Float] {
        (0 ..< Int(seconds * sampleRate)).map { Float(0.4 * sin(2 * Double.pi * 440 * Double($0) / sampleRate)) }
    }
}
