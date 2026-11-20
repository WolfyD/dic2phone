import XCTest
@testable import Dic2Phone

final class SilenceFinderTests: XCTestCase {
    private static let samplesPerMs = SpeechPieces.sampleRate / 1000
    private static let speech: Float = 0.3
    private static let hush: Float = 0.0005

    func testALongQuietStretchBecomesAGapLessWhatIsKept() {
        let gaps = Self.gaps(of: [(Self.speech, 2000), (Self.hush, 3000), (Self.speech, 2000)])
        XCTAssertEqual(gaps, [SilenceGap(fromMs: 2300, toMs: 4700)])
    }

    func testAPauseBetweenWordsIsLeftAlone() {
        let gaps = Self.gaps(of: [(Self.speech, 2000), (Self.hush, 800), (Self.speech, 2000)])
        XCTAssertEqual(gaps, [])
    }

    func testAOneWindowBlipDoesNotBreakASilence() {
        let blip: Float = 0.002
        let gaps = Self.gaps(of: [(Self.speech, 2000), (Self.hush, 1500), (blip, 50), (Self.hush, 1500), (Self.speech, 2000)])
        XCTAssertEqual(gaps, [SilenceGap(fromMs: 2300, toMs: 4750)])
    }

    func testQuietAtTheEndOfTheTapeIsAGapToo() {
        let gaps = Self.gaps(of: [(Self.speech, 2000), (Self.hush, 2000)])
        XCTAssertEqual(gaps, [SilenceGap(fromMs: 2300, toMs: 3700)])
    }

    func testNothingDecodedFindsNothing() {
        XCTAssertEqual(SilenceFinder().gaps(), [])
    }

    func testAGapIsSkippedUntilJustBeforeItsEnd() {
        let gap = SilenceGap(fromMs: 1000, toMs: 2000)
        XCTAssertFalse(gap.isSkippable(atMs: 999))
        XCTAssertTrue(gap.isSkippable(atMs: 1000))
        XCTAssertTrue(gap.isSkippable(atMs: 1940))
        XCTAssertFalse(gap.isSkippable(atMs: 1960))
    }

    /// A tape of steady tones, each `(amplitude, ms)`, fed in uneven pieces as a decoder would.
    private static func gaps(of stretches: [(Float, Int)]) -> [SilenceGap] {
        let samples = stretches.flatMap { amplitude, ms in
            (0 ..< ms * samplesPerMs).map { $0.isMultiple(of: 2) ? amplitude : -amplitude }
        }
        var finder = SilenceFinder()
        var start = 0
        while start < samples.count {
            let end = min(start + 1234, samples.count)
            finder.append(Array(samples[start ..< end]))
            start = end
        }
        return finder.gaps()
    }
}
