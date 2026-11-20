import XCTest
@testable import Dic2Phone

final class SpeechPiecesTests: XCTestCase {
    private let second = SpeechPieces.sampleRate

    func testAShortTapeIsOnePieceAtTheEnd() throws {
        var pieces = SpeechPieces()

        XCTAssertTrue(pieces.append(speech(seconds: 3)).isEmpty)
        let piece = try XCTUnwrap(pieces.finish())

        XCTAssertEqual(piece.start, 0)
        XCTAssertEqual(piece.samples.count, 3 * second)
    }

    func testSilenceIsSkipped() {
        var pieces = SpeechPieces()

        XCTAssertTrue(pieces.append([Float](repeating: 0, count: 3 * second)).isEmpty)
        XCTAssertNil(pieces.finish())
    }

    func testAnEndingTooShortForAWordIsDropped() {
        var pieces = SpeechPieces()
        _ = pieces.append(speech(seconds: 0.2))

        XCTAssertNil(pieces.finish())
    }

    func testALongTapeIsCutInTheQuietNearFiveMinutes() throws {
        var pieces = SpeechPieces()
        let pauseStart = 310 * second
        var samples = speech(seconds: 340)
        samples.replaceSubrange(pauseStart..<pauseStart + second / 5, with: [Float](repeating: 0, count: second / 5))

        let first = try XCTUnwrap(pieces.append(samples).first)
        let rest = try XCTUnwrap(pieces.finish())

        let cut = pauseStart + second / 20
        XCTAssertEqual(first.start, 0)
        XCTAssertEqual(first.samples.count, cut)
        XCTAssertEqual(rest.start, Int64(cut))
        XCTAssertEqual(rest.startMs, Int64(cut) * 1000 / Int64(second))
        XCTAssertEqual(rest.samples.count, samples.count - cut)
    }

    private func speech(seconds: Double) -> [Float] {
        (0..<Int(seconds * Double(second))).map { $0.isMultiple(of: 2) ? 0.1 : -0.1 }
    }
}
