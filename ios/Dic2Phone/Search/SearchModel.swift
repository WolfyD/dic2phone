import Observation

/// Searching what was said on every transcribed tape: the deck's, the shelf's, and the vault's
/// while it's open.
@MainActor
@Observable
final class SearchModel {
    /// Playing from a hit starts a little early, so the words aren't clipped.
    private static let leadInMs: Int64 = 300

    var query = ""
    private(set) var isReading = true

    @ObservationIgnored private let library: TapeLibrary
    @ObservationIgnored private let player: Player
    @ObservationIgnored private let vault: Vault
    @ObservationIgnored let goBack: () -> Void

    init(library: TapeLibrary, player: Player, vault: Vault, goBack: @escaping () -> Void) {
        self.library = library
        self.player = player
        self.vault = vault
        self.goBack = goBack
    }

    var transcribedTapes: [Tape] {
        (library.deck + library.shelf + library.vault).filter(\.hasCaptions)
    }

    var vaultIsLocked: Bool {
        !vault.isOpen
    }

    var hits: [CaptionHit] {
        let index = transcribedTapes.compactMap { tape in
            library.transcripts[tape.id].map { (tape: tape, transcript: $0) }
        }
        return CaptionSearch.hits(for: query, in: index)
    }

    /// The transcript of the tape playing from a hit.
    var playing: (tape: Tape, transcript: Transcript)? {
        guard let id = player.playingID, let tape = library.tape(id), let transcript = library.transcripts[id] else { return nil }
        return (tape, transcript)
    }

    func readTranscripts() async {
        for tape in transcribedTapes {
            await library.loadTranscript(of: tape)
        }
        isReading = false
    }

    func play(_ hit: CaptionHit) {
        player.play(hit.tape, fromMs: max(hit.cue.startMs - Self.leadInMs, 0))
    }

    /// Leaving the search stops its tape, as leaving a list does.
    func leave() {
        player.stop()
    }
}
