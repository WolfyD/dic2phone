import Observation
import UIKit
import UniformTypeIdentifiers

/// A tape's transcript being read: playing from a line, and copying, sending or remaking it.
@MainActor
@Observable
final class TranscriptModel {
    let tape: Tape
    /// What the share sheet is sending: the text, or the .srt file.
    private(set) var sharing: [Any]?
    var confirmingRedo = false
    var notice: String?

    @ObservationIgnored private let library: TapeLibrary
    @ObservationIgnored private let player: Player
    @ObservationIgnored private let captions: CaptionQueue
    @ObservationIgnored let close: () -> Void

    init(tape: Tape, library: TapeLibrary, player: Player, captions: CaptionQueue, close: @escaping () -> Void) {
        self.tape = tape
        self.library = library
        self.player = player
        self.captions = captions
        self.close = close
    }

    /// Nil until it has been read.
    var transcript: Transcript? {
        library.transcripts[tape.id]
    }

    /// Erased, or out of sight in a vault that locked.
    var tapeIsGone: Bool {
        library.tape(tape.id) == nil
    }

    var isPlaying: Bool {
        player.playingID == tape.id
    }

    var positionMs: Int64 {
        player.positionMs
    }

    /// The line being spoken, while the tape plays.
    var currentIndex: Int? {
        guard isPlaying else { return nil }
        return transcript?.index(atMs: player.positionMs)
    }

    var hasSpeech: Bool {
        transcript?.cues.isEmpty == false
    }

    func load() async {
        await library.loadTranscript(of: tape)
    }

    func play(from cue: Cue) {
        player.play(tape, fromMs: cue.startMs)
    }

    func stop() {
        player.stop()
    }

    func copy() {
        guard let text = readableText else { return }
        // Universal Clipboard would hand a vault tape's words to the user's other devices.
        let options: [UIPasteboard.OptionsKey: Any] = tape.rack == .vault ? [.localOnly: true] : [:]
        UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: text]], options: options)
        notice = String(localized: "Transcript copied")
    }

    func sendText() {
        guard let text = readableText else { return }
        sharing = [text]
    }

    func sendCaptions() {
        Task {
            guard let file = await library.captionsToSend(of: tape) else {
                notice = String(localized: "Couldn't make the subtitles file")
                return
            }
            sharing = [file]
        }
    }

    /// Called both when the share sheet reports back and when it's swiped away.
    func finishSharing() {
        guard sharing != nil else { return }
        sharing = nil
        if tape.rack == .vault {
            Task { await library.clearSendingCopies() }
        }
    }

    func redo() {
        captions.transcribe([tape])
        close()
    }

    private var readableText: String? {
        guard let transcript, hasSpeech else { return nil }
        return transcript.readable(heading: String(localized: "Transcript · Dic2Phone tape \(TapeNames.label(tape))"))
    }
}
