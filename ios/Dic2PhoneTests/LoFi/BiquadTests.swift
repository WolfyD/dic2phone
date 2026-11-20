import XCTest
@testable import Dic2Phone

final class BiquadTests: XCTestCase {
    private static let sampleRate = 44_100.0

    func testALowpassLetsALowToneThroughAndStopsAHighOne() {
        XCTAssertEqual(Self.gain(of: .lowpass(sampleRate: Self.sampleRate, hz: 3400, q: 0.7), atHz: 200), 1, accuracy: 0.05)
        XCTAssertLessThan(Self.gain(of: .lowpass(sampleRate: Self.sampleRate, hz: 3400, q: 0.7), atHz: 15_000), 0.1)
    }

    func testAHighpassStopsALowToneAndLetsAHighOneThrough() {
        XCTAssertLessThan(Self.gain(of: .highpass(sampleRate: Self.sampleRate, hz: 160, q: 0.7), atHz: 20), 0.1)
        XCTAssertEqual(Self.gain(of: .highpass(sampleRate: Self.sampleRate, hz: 160, q: 0.7), atHz: 2000), 1, accuracy: 0.05)
    }

    func testAPeakLiftsItsOwnFrequency() {
        let lifted = Self.gain(of: .peak(sampleRate: Self.sampleRate, hz: 1300, q: 0.9, gainDb: 6), atHz: 1300)
        XCTAssertEqual(lifted, 2, accuracy: 0.1)
    }

    /// How much louder a steady tone comes out than it went in, once the filter has settled.
    private static func gain(of filter: Biquad, atHz hz: Double) -> Float {
        var filter = filter
        let tone = (0 ..< Int(sampleRate / 2)).map { Float(sin(2 * Double.pi * hz * Double($0) / sampleRate)) }
        let out = tone.map { filter.filter($0) }
        let settled = out.suffix(out.count / 2)
        return (settled.map(abs).max() ?? 0) / (tone.map(abs).max() ?? 1)
    }
}
