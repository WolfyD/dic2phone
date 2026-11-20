import XCTest
@testable import Dic2Phone

final class SnapDetectorTests: XCTestCase {
    /// The detector's analysis block; the sounds below are whole blocks so a crack fills one.
    private static let block = 256
    private static let silence = [Int16](repeating: 0, count: block * 60)
    /// A crack at the highest frequency there is, the purest form of a snap.
    private static let crack: [Int16] = (0..<block).map { $0.isMultiple(of: 2) ? 16_000 : -16_000 }
    private static let afterwards = [Int16](repeating: 0, count: block * 40)
    /// A 200 Hz tone: all body, like a voice's vowels.
    private static let talking: [Int16] = (0..<block * 40).map {
        Int16(8_000 * sin(2 * Double.pi * 200 * Double($0) / Double(TapeFormat.sampleRate)))
    }

    func testHearsASnapOutOfSilence() {
        var detector = SnapDetector()
        XCTAssertTrue(detector.feed(Self.silence + Self.crack + Self.afterwards))
    }

    func testSilenceIsNoSnap() {
        var detector = SnapDetector()
        XCTAssertFalse(detector.feed(Self.silence + Self.afterwards))
    }

    func testTalkingIsNoSnap() {
        var detector = SnapDetector()
        XCTAssertFalse(detector.feed(Self.silence + Self.talking))
    }

    func testACrackFollowedByTalkingIsNoSnap() {
        var detector = SnapDetector()
        XCTAssertFalse(detector.feed(Self.silence + Self.crack + Self.talking))
    }

    func testASecondSnapRightAfterTheFirstIsIgnored() {
        var detector = SnapDetector()
        XCTAssertTrue(detector.feed(Self.silence + Self.crack + Self.afterwards))
        XCTAssertFalse(detector.feed(Self.silence + Self.crack + Self.afterwards))
    }
}
