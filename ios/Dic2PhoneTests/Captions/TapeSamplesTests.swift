import AVFoundation
import CryptoKit
import XCTest
@testable import Dic2Phone

final class TapeSamplesTests: XCTestCase {
    private static let seconds = 2
    private var root: URL!
    private var tapeURL: URL!

    override func setUp() async throws {
        root = try URL.temporaryFolder()
        tapeURL = root.appending(path: "tape.m4a")
        try await recordTone(to: tapeURL)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testDecodesAPlainTapeTo16kHz() async throws {
        let samples = try await decodeAll(TapeSamples(asset: AVURLAsset(url: tapeURL)))

        assertIsTheTone(samples)
    }

    func testDecodesASealedTapeWithoutUnsealingIt() async throws {
        let key = SymmetricKey(size: .bits256)
        let sealedURL = root.appending(path: "tape.d2pv")
        try SealedFileWriter.seal(contentsOf: tapeURL, to: sealedURL, key: key)
        let loader = SealedAssetLoader(file: SealedFile(url: sealedURL, key: key))
        let asset = try XCTUnwrap(loader.makeAsset())

        let samples = try await decodeAll(TapeSamples(asset: asset, loader: loader))

        assertIsTheTone(samples)
    }

    func testRefusesAFileThatIsNotATape() async throws {
        let junk = root.appending(path: "junk.m4a")
        try Data("not audio".utf8).write(to: junk)

        do {
            _ = try await TapeSamples(asset: AVURLAsset(url: junk))
            XCTFail("Decoded junk")
        } catch {
            XCTAssertEqual(error as? CaptionError, .tapeUnreadable)
        }
    }

    private func decodeAll(_ tape: TapeSamples) throws -> [Float] {
        var samples: [Float] = []
        while let more = try tape.next() {
            samples += more
        }
        return samples
    }

    /// AAC adds a little padding, so the length is only about right.
    private func assertIsTheTone(_ samples: [Float], file: StaticString = #filePath, line: UInt = #line) {
        let expected = Self.seconds * SpeechPieces.sampleRate
        XCTAssertEqual(Double(samples.count), Double(expected), accuracy: Double(SpeechPieces.sampleRate) * 0.1, file: file, line: line)
        let loudest = samples.map(abs).max() ?? 0
        XCTAssertGreaterThan(loudest, 0.1, file: file, line: line)
    }

    private func recordTone(to url: URL) async throws {
        let writer = try AssetTapeWriter(url: url)
        let chunk = (0..<TapeFormat.chunkSize).map { Int16(8_000 * sin(Double($0) * 0.1)) }
        let chunkCount = TapeFormat.sampleRate * Self.seconds / TapeFormat.chunkSize
        for index in 0..<chunkCount {
            try await writer.append(chunk, at: Int64(index * TapeFormat.chunkSize))
        }
        _ = await writer.finish()
    }
}
