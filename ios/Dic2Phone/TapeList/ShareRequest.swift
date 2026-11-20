import Foundation

/// Tapes on their way to the share sheet, and the files that carry them.
struct ShareRequest {
    let tapes: [Tape]
    let files: [URL]
}
