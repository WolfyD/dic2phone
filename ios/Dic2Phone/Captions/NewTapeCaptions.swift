import UIKit

/// Queues captions for tapes just recorded, when Setup asks for that and a model is ready.
@MainActor
final class NewTapeCaptions {
    private let settings: Settings
    private let models: ModelStore
    private let library: TapeLibrary
    private let queue: CaptionQueue
    private var waiting: [TapeID] = []

    init(settings: Settings, models: ModelStore, library: TapeLibrary, queue: CaptionQueue) {
        self.settings = settings
        self.models = models
        self.library = library
        self.queue = queue
    }

    func recorded(_ tapes: [TapeID]) {
        guard settings.autoCaptions == .afterRecording, !tapes.isEmpty else { return }
        waiting += tapes
        // A tape recorded in a locked phone can't be read until it's unlocked.
        if UIApplication.shared.isProtectedDataAvailable { queueWaiting() }
    }

    /// The phone was unlocked and Dic2Phone came back.
    func appBecameActive() {
        queueWaiting()
    }

    private func queueWaiting() {
        defer { waiting = [] }
        guard settings.autoCaptions == .afterRecording,
              let model = settings.speechModel,
              models.isDownloaded(model)
        else { return }
        queue.transcribe(waiting.compactMap { library.tape($0) })
    }
}
