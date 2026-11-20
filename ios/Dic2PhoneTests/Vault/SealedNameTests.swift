import XCTest
@testable import Dic2Phone

final class SealedNameTests: XCTestCase {
    func testTwentyFourLowercaseHexDigitsAreAName() {
        XCTAssertNotNil(SealedName("0123456789abcdef01234567"))
    }

    func testAnythingElseIsRejected() {
        let rejected = [
            "",
            "0123456789abcdef0123456",
            "0123456789abcdef012345678",
            "0123456789ABCDEF01234567",
            "../../../../etc/passwd00",
            "0123456789abcdef0123456/",
            "0123456789abcdef0123456g",
        ]
        for value in rejected {
            XCTAssertNil(SealedName(value), value)
        }
    }

    func testRandomNamesAreValidAndDiffer() {
        let names = (0..<50).map { _ in SealedName.random() }
        XCTAssertTrue(names.allSatisfy { SealedName($0.value) != nil })
        XCTAssertEqual(Set(names).count, names.count)
    }
}
