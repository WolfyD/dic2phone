/// One caption: what was said between two moments of a tape.
struct Cue: Equatable, Sendable {
    var startMs: Int64
    var endMs: Int64
    var text: String
}
