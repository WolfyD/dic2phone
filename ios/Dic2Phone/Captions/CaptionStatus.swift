/// What the caption queue is doing right now.
struct CaptionStatus: Equatable, Sendable {
    /// The tape being worked on; nil while only a model is being fetched.
    let tape: TapeID?
    let step: CaptionStep
    let percent: Int
    /// Which job this is, counting from 1, and how many there are in all.
    let index: Int
    let total: Int
}
