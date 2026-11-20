/// What a key does: something on a tap, or one thing when pressed and another when let go.
enum KeyAction {
    case tap(@MainActor () -> Void)
    case hold(press: @MainActor () -> Void, release: @MainActor () -> Void)
}
