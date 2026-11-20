/// Plays the key click. Views take it from the environment, so they never hold the sound player.
struct KeyClick {
    let play: @MainActor () -> Void

    @MainActor
    func callAsFunction() {
        play()
    }
}
