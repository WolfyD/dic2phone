import Foundation

enum SealedFileError: Error {
    case notSealed
    /// Cut short, reordered or otherwise not what was written.
    case damaged
    case unwritable
}
