import Foundation

/// A tape's file name, such as `2026-11-19_14-03-22.m4a` or `2026-11-19_14-03-22_2.m4a`.
///
/// Every path to a tape, its metadata or its captions is built from one of these, and one can
/// only be made from a name of exactly this shape, so no string from a file, a share or a
/// widget can ever point outside the app's own folders (CWE-22).
struct TapeID: Hashable, Comparable, Sendable {
    static let fileExtension = "m4a"
    private static let stampShape = Array("dddd-dd-dd_dd-dd-dd")
    private static let maxCopyDigits = 4

    let fileName: String

    init?(_ fileName: String) {
        guard Self.isValid(fileName) else { return nil }
        self.fileName = fileName
    }

    init(startedAt date: Date, copy: Int = 1) {
        let stamp = Self.stampFormatter.string(from: date)
        fileName = (copy > 1 ? "\(stamp)_\(copy)" : stamp) + "." + Self.fileExtension
    }

    /// The name without its extension, used for metadata and caption files.
    var baseName: String { String(fileName.dropLast(Self.fileExtension.count + 1)) }

    var recordedAt: Date? {
        Self.stampFormatter.date(from: String(fileName.prefix(Self.stampShape.count)))
    }

    static func < (lhs: TapeID, rhs: TapeID) -> Bool { lhs.fileName < rhs.fileName }

    private static func isValid(_ name: String) -> Bool {
        let suffix = "." + fileExtension
        guard name.hasSuffix(suffix) else { return false }
        let base = Array(name.dropLast(suffix.count))
        guard base.count >= stampShape.count else { return false }
        let stampMatches = zip(base, stampShape).allSatisfy { char, shape in
            shape == "d" ? char.isASCII && char.isNumber : char == shape
        }
        guard stampMatches else { return false }
        let copy = base.dropFirst(stampShape.count)
        guard let underscore = copy.first else { return true }
        let digits = copy.dropFirst()
        return underscore == "_"
            && (1...maxCopyDigits).contains(digits.count)
            && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}
