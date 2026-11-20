import Foundation

/// The whisper.cpp models the app can download. Each is pinned to the exact file it was tested
/// with: a download whose size or SHA-256 differs is thrown away (CWE-494).
enum SpeechModel: String, CaseIterable, Sendable {
    case base
    case small

    var fileName: String {
        switch self {
        case .base: "ggml-base-q5_1.bin"
        case .small: "ggml-small-q5_1.bin"
        }
    }

    var sha256: String {
        switch self {
        case .base: "422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898"
        case .small: "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb"
        }
    }

    var sizeBytes: Int64 {
        switch self {
        case .base: 59_707_625
        case .small: 190_085_487
        }
    }

    var name: String {
        switch self {
        case .base: String(localized: "BASE")
        case .small: String(localized: "SMALL")
        }
    }

    var sizeLabel: String {
        switch self {
        case .base: String(localized: "57 MB")
        case .small: String(localized: "181 MB")
        }
    }

    var note: String {
        switch self {
        case .base: String(localized: "quick, fine for clear English")
        case .small: String(localized: "~3× slower, much better for Hungarian and other languages")
        }
    }

    var downloadURL: URL? {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")
    }
}
