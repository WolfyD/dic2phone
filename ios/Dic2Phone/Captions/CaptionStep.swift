/// One step of making captions, as the status line names it.
enum CaptionStep: Equatable, Sendable {
    case fetching(SpeechModel)
    case loading
    case listening

    var line: String {
        switch self {
        case .fetching(let model): String(localized: "FETCHING \(model.name) MODEL")
        case .loading: String(localized: "LOADING MODEL")
        case .listening: String(localized: "LISTENING")
        }
    }
}
