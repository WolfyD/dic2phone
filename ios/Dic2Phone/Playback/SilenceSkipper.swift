/// The silences SKIP SILENCE jumps over on the tape playing. A tape's silences are found the
/// first time it plays with skipping on, by listening through it in the background, and are
/// remembered until the app closes or the tape moves.
@MainActor
final class SilenceSkipper {
    private var known: [TapeID: [SilenceGap]] = [:]
    private var playing: TapeID?
    private var search: Task<Void, Never>?

    func prepare(_ tape: Tape, from source: TapeSource) {
        playing = tape.id
        guard known[tape.id] == nil, search == nil else { return }
        search = Task { [weak self] in
            let gaps = try? await SilenceFinder.gaps(in: source)
            guard let self, !Task.isCancelled else { return }
            known[tape.id] = gaps
            search = nil
        }
    }

    func stop() {
        search?.cancel()
        search = nil
        playing = nil
    }

    /// Where to jump to from `ms`, if it's inside a silence.
    func jump(fromMs ms: Int64) -> Int64? {
        guard let playing else { return nil }
        return known[playing]?.first { $0.isSkippable(atMs: ms) }?.toMs
    }

    func forget(_ ids: Set<TapeID>) {
        known = known.filter { !ids.contains($0.key) }
    }
}
