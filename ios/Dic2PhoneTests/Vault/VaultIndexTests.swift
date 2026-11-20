import CryptoKit
import XCTest
@testable import Dic2Phone

final class VaultIndexTests: XCTestCase {
    private let key = SymmetricKey(size: .bits256)
    private let entries = [
        VaultEntry(
            id: Tape.fixture("2026-11-19_14-03-22").id,
            name: SealedName.random(),
            durationMs: 60_000,
            sizeBytes: 720_000,
            addedAtMs: 1_795_000_000_000
        ),
        VaultEntry(
            id: Tape.fixture("2026-11-20_09-00-00").id,
            name: SealedName.random(),
            durationMs: 1_000,
            sizeBytes: 12_000,
            addedAtMs: 1_795_100_000_000
        ),
    ]

    func testEntriesComeBackAsTheyWent() throws {
        XCTAssertEqual(try VaultIndex.open(VaultIndex.seal(entries, key: key), key: key), entries)
    }

    func testTheIndexHidesTheTapesNames() throws {
        let sealed = try VaultIndex.seal(entries, key: key)
        XCTAssertNil(sealed.firstRange(of: Data("2026-11-19".utf8)))
    }

    func testTheWrongKeyOpensNothing() throws {
        let sealed = try VaultIndex.seal(entries, key: key)
        XCTAssertThrowsError(try VaultIndex.open(sealed, key: SymmetricKey(size: .bits256)))
    }

    func testAChangedByteIsCaught() throws {
        var sealed = try VaultIndex.seal(entries, key: key)
        sealed[sealed.count / 2] ^= 0x01
        XCTAssertThrowsError(try VaultIndex.open(sealed, key: key))
    }
}
