/// Which old-portable-recorder effects go into a tape's effect copy.
struct TapeEffects: Hashable, Sendable {
    /// Cheap-tape hiss and a faint transport-motor whine.
    var hiss = true
    /// Dull, narrow tone: worn head, small mic.
    var muffle = true
    /// Slight pitch wobble from an uneven capstan.
    var wow = true
    /// Soft tape compression: loud bits squashed, quiet bits lifted.
    var saturate = true

    var any: Bool {
        hiss || muffle || wow || saturate
    }

    /// One number per combination, naming the folder its copies are kept in. The same bits as
    /// Android's.
    var mask: Int {
        (hiss ? 1 : 0) | (muffle ? 2 : 0) | (wow ? 4 : 0) | (saturate ? 8 : 0)
    }
}
