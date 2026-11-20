import SwiftUI

/// A piano key that acts for as long as it's held (REC, REW, FF). The press follows the finger
/// wherever it goes, so starting to record can re-lay out the deck under it without ending
/// the press.
struct HoldKey<Label: View>: View {
    let height: CGFloat
    let face1: Color
    let face2: Color
    let latched: Bool
    let onPress: @MainActor () -> Void
    let onRelease: @MainActor () -> Void
    @ViewBuilder let label: Label

    @GestureState private var touching = false
    @State private var holding = false

    var body: some View {
        let pressed = touching || latched
        PianoKey(down: pressed ? 1 : 0, height: height, face1: face1, face2: face2) {
            label
        }
        .animation(KeyMotion.spring(pressed: pressed), value: pressed)
        .contentShape(Rectangle())
        // A gesture state resets by itself when the system cancels the touch, which a drag's
        // end handler never hears about.
        .gesture(DragGesture(minimumDistance: 0).updating($touching) { _, touching, _ in touching = true })
        .onChange(of: touching) { _, touching in
            touching ? press() : release()
        }
        // Never leave a hold running when the key goes away mid-press.
        .onDisappear(perform: release)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            press()
            release()
        }
    }

    private func press() {
        holding = true
        onPress()
    }

    private func release() {
        guard holding else { return }
        holding = false
        onRelease()
    }
}
