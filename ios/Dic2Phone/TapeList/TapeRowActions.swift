import Foundation

/// What a tape row does: a tap, a long press to select it, and its ⏏ key.
struct TapeRowActions {
    let tap: () -> Void
    let select: () -> Void
    let load: () -> Void
}
