import SwiftUI

/// A button drawn as a piano key that sinks while pressed, or stays down while `latched`.
struct PianoKeyStyle: ButtonStyle {
    let height: CGFloat
    let face1: Color
    let face2: Color
    let latched: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || latched
        PianoKey(down: pressed ? 1 : 0, height: height, face1: face1, face2: face2) {
            configuration.label
        }
        .animation(KeyMotion.spring(pressed: pressed), value: pressed)
    }
}
