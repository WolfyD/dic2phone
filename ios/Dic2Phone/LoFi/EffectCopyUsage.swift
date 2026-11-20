/// How many effect copies are kept, and the space they take.
struct EffectCopyUsage: Equatable, Sendable {
    var count = 0
    var bytes: Int64 = 0
}
