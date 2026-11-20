import XCTest
@testable import Dic2Phone

final class SoundClipTests: XCTestCase {
    func testClampsThenScalesToSixteenBits() {
        let clip = SoundClip([2, -2, 0.5, 0], sampleRate: 8_000, fullScale: 32_767)
        XCTAssertEqual(clip.samples, [32_767, -32_767, 16_383, 0])
    }

    func testWAVHeaderDescribesSixteenBitMono() {
        let wav = SoundClip([0.5, -0.5, 0], sampleRate: 8_000, fullScale: 32_767).wavData

        XCTAssertEqual(wav.count, 44 + 3 * 2)
        XCTAssertEqual(String(decoding: wav[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(Self.uint32(wav, at: 4), 36 + 3 * 2)
        XCTAssertEqual(String(decoding: wav[8..<16], as: UTF8.self), "WAVEfmt ")
        XCTAssertEqual(Self.uint16(wav, at: 22), 1, "channels")
        XCTAssertEqual(Self.uint32(wav, at: 24), 8_000, "sample rate")
        XCTAssertEqual(Self.uint32(wav, at: 28), 16_000, "bytes per second")
        XCTAssertEqual(Self.uint16(wav, at: 34), 16, "bits per sample")
        XCTAssertEqual(String(decoding: wav[36..<40], as: UTF8.self), "data")
        XCTAssertEqual(Self.uint32(wav, at: 40), 3 * 2)
    }

    func testWAVSamplesAreLittleEndian() {
        let wav = SoundClip([-1], sampleRate: 8_000, fullScale: 2).wavData
        XCTAssertEqual(Array(wav[44..<46]), [0xFE, 0xFF])
    }

    private static func uint16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { value, byte in value | UInt32(data[offset + byte]) << (8 * byte) }
    }
}
