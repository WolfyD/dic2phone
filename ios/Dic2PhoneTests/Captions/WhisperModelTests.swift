import XCTest
@testable import Dic2Phone

final class WhisperModelTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = try URL.temporaryFolder()
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    func testAFileThatIsNoSpeechModelIsRefused() throws {
        let file = folder.appending(path: "model.bin")
        try Data("not a speech model".utf8).write(to: file)

        XCTAssertThrowsError(try WhisperModel(contentsOf: file))
    }

    func testAMissingModelIsRefused() {
        XCTAssertThrowsError(try WhisperModel(contentsOf: folder.appending(path: "missing.bin")))
    }
}
