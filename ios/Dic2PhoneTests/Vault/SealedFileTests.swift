import CryptoKit
import XCTest
@testable import Dic2Phone

final class SealedFileTests: XCTestCase {
    private static let chunk = SealedFormat.chunkSize

    private var root: URL!
    private let key = SymmetricKey(size: .bits256)

    override func setUpWithError() throws {
        root = try URL.temporaryFolder()
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testEverySizeComesBackAsItWent() throws {
        for size in [0, 1, 1000, Self.chunk - 1, Self.chunk, Self.chunk + 1, 3 * Self.chunk + 123] {
            let plain = RandomBytes.make(size)
            let reader = try SealedFileReader(url: seal(plain), key: key)
            XCTAssertEqual(reader.size, Int64(size), "size \(size)")
            XCTAssertEqual(try reader.readAll(), plain, "size \(size)")
        }
    }

    func testReadsFromAnywhereMatchThePlainBytes() throws {
        let plain = RandomBytes.make(3 * Self.chunk + 500)
        let reader = try SealedFileReader(url: seal(plain), key: key)
        let reads: [(offset: Int, count: Int)] = [
            (0, 10),
            (Self.chunk - 5, 10),
            (Self.chunk, Self.chunk),
            (100, 2 * Self.chunk + 300),
            (3 * Self.chunk + 499, 1),
        ]
        for read in reads {
            let expected = plain.subdata(in: read.offset..<(read.offset + read.count))
            XCTAssertEqual(try reader.read(from: Int64(read.offset), count: read.count), expected, "at \(read.offset)")
        }
    }

    func testAReadPastTheEndStopsAtTheEnd() throws {
        let plain = RandomBytes.make(1000)
        let reader = try SealedFileReader(url: seal(plain), key: key)
        XCTAssertEqual(try reader.read(from: 900, count: 500), plain.suffix(100))
        XCTAssertEqual(try reader.read(from: 2000, count: 10), Data())
    }

    func testACopyHoldsThePlainBytes() throws {
        let plain = RandomBytes.make(2 * Self.chunk + 7)
        let copy = root.appending(path: "copy")
        try SealedFileReader(url: seal(plain), key: key).copy(to: copy)
        XCTAssertEqual(try Data(contentsOf: copy), plain)
    }

    func testTheFileHoldsNoPlainBytes() throws {
        let sealed = try Data(contentsOf: seal(Data(repeating: 0x41, count: 4096)))
        XCTAssertNil(sealed.firstRange(of: Data(repeating: 0x41, count: 64)))
    }

    func testAChangedByteIsCaught() throws {
        let url = try seal(RandomBytes.make(Self.chunk + 100))
        try change(url) { bytes in bytes[SealedFormat.headerSize + SealedFormat.nonceSize + 5] ^= 0x01 }
        XCTAssertThrowsError(try SealedFileReader(url: url, key: key).readAll())
    }

    func testCuttingOffTheLastRecordIsCaught() throws {
        let url = try seal(RandomBytes.make(2 * Self.chunk + 100))
        try change(url) { bytes in bytes = bytes.prefix(SealedFormat.headerSize + 2 * SealedFormat.recordSize) }
        XCTAssertThrowsError(try SealedFileReader(url: url, key: key).readAll())
    }

    func testSwappedRecordsAreCaught() throws {
        let url = try seal(RandomBytes.make(2 * Self.chunk + 100))
        try change(url) { bytes in
            let first = Self.record(0, of: bytes)
            let second = Self.record(1, of: bytes)
            bytes.replaceSubrange(first.range, with: second.bytes)
            bytes.replaceSubrange(second.range, with: first.bytes)
        }
        XCTAssertThrowsError(try SealedFileReader(url: url, key: key).read(from: 0, count: 10))
    }

    func testARecordFromAnotherFileIsCaught() throws {
        let url = try seal(RandomBytes.make(Self.chunk + 100), name: "a")
        let other = try Data(contentsOf: seal(RandomBytes.make(Self.chunk + 100), name: "b"))
        try change(url) { bytes in
            bytes.replaceSubrange(Self.record(0, of: bytes).range, with: Self.record(0, of: other).bytes)
        }
        XCTAssertThrowsError(try SealedFileReader(url: url, key: key).read(from: 0, count: 10))
    }

    func testTheWrongKeyOpensNothing() throws {
        let url = try seal(RandomBytes.make(100))
        XCTAssertThrowsError(try SealedFileReader(url: url, key: SymmetricKey(size: .bits256)).readAll())
    }

    func testAPlainFileIsNotSealed() throws {
        let url = root.appending(path: "plain")
        try RandomBytes.make(500).write(to: url)
        XCTAssertThrowsError(try SealedFileReader(url: url, key: key)) { error in
            XCTAssertEqual(error as? SealedFileError, .notSealed)
        }
    }

    private func seal(_ plain: Data, name: String = "sealed") throws -> URL {
        let url = root.appending(path: name)
        try? FileManager.default.removeItem(at: url)
        try SealedFileWriter.seal(plain, to: url, key: key)
        return url
    }

    private func change(_ url: URL, _ edit: (inout Data) -> Void) throws {
        var bytes = try Data(contentsOf: url)
        edit(&bytes)
        try bytes.write(to: url)
    }

    private static func record(_ index: Int, of bytes: Data) -> (range: Range<Int>, bytes: Data) {
        let start = SealedFormat.headerSize + index * SealedFormat.recordSize
        let range = start..<(start + SealedFormat.recordSize)
        return (range, bytes.subdata(in: range))
    }
}
