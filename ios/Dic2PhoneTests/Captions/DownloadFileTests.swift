import XCTest
@testable import Dic2Phone

final class DownloadFileTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = try URL.temporaryFolder()
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testHashesWhatItWrites() throws {
        let url = root.appending(path: "model.part")
        let file = try DownloadFile(at: url, sizeLimit: 3)

        try file.append(Data("ab".utf8))
        try file.append(Data("c".utf8))

        XCTAssertEqual(try file.finish(), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(try Data(contentsOf: url), Data("abc".utf8))
    }

    func testRefusesToGrowPastItsSize() throws {
        let file = try DownloadFile(at: root.appending(path: "model.part"), sizeLimit: 2)

        XCTAssertThrowsError(try file.append(Data("abc".utf8))) { error in
            XCTAssertEqual(error as? CaptionError, .downloadCorrupted)
        }
    }
}
