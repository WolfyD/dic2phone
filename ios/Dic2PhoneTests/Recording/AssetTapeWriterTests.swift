import AVFoundation
import XCTest
@testable import Dic2Phone

final class AssetTapeWriterTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".m4a")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Six seconds spans more than one five-second movie fragment.
    func testWritesAPlayableTapeAcrossFragments() async throws {
        let writer = try AssetTapeWriter(url: url)
        let chunk = (0..<TapeFormat.chunkSize).map { Int16(8_000 * sin(Double($0) * 0.1)) }
        let chunkCount = TapeFormat.sampleRate * 6 / TapeFormat.chunkSize
        for index in 0..<chunkCount {
            try await writer.append(chunk, at: Int64(index * TapeFormat.chunkSize))
        }
        let written = await writer.finish()

        XCTAssertTrue(written)
        let asset = AVURLAsset(url: url)
        let seconds = try await asset.load(.duration).seconds
        let expected = Double(chunkCount * TapeFormat.chunkSize) / Double(TapeFormat.sampleRate)
        XCTAssertEqual(seconds, expected, accuracy: 0.1)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 1)
    }

    func testRefusesAnEmptyChunk() async throws {
        let writer = try AssetTapeWriter(url: url)
        var refused = false
        do {
            try await writer.append([], at: 0)
        } catch {
            refused = true
        }
        _ = await writer.finish()

        XCTAssertTrue(refused)
    }
}
