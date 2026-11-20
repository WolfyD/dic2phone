/// One thing waiting in the caption queue.
enum CaptionJob: Sendable {
    case caption(Tape)
    /// Just download a model, from Setup.
    case fetch(SpeechModel)

    var tapeID: TapeID? {
        if case .caption(let tape) = self { tape.id } else { nil }
    }

    var model: SpeechModel? {
        if case .fetch(let model) = self { model } else { nil }
    }

    var isVaultTape: Bool {
        switch self {
        case .caption(let tape): tape.rack == .vault
        case .fetch: false
        }
    }
}
