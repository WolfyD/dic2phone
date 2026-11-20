/// A place on a tape where the searched words were said.
struct CaptionHit: Sendable {
    let tape: Tape
    let cue: Cue
    /// Where the words are in the cue's text, counted in characters.
    let characters: Range<Int>
}
