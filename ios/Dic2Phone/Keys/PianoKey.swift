import SwiftUI

/// A mechanical piano key seen from slightly above: a top face and a darker front lip, sitting in
/// a black well. Pressing sinks it: the face drops, most of the lip disappears into the chassis
/// and a strip of the dark well opens above it.
struct PianoKey<Label: View>: View, Animatable {
    /// How far the key is pressed, 0...1. Animate it for the "thunk".
    var down: CGFloat
    let height: CGFloat
    let face1: Color
    let face2: Color
    @ViewBuilder let label: Label

    var animatableData: CGFloat {
        get { down }
        set { down = newValue }
    }

    private var lip: CGFloat { min(height * 0.2, 14) }
    private var travel: CGFloat { min(height * 0.08, 6) }

    var body: some View {
        let art = PianoKeyArt(down: down, lip: lip, travel: travel, face1: face1, face2: face2)
        ZStack {
            Canvas { context, size in
                art.draw(in: context, size: size)
            }
            label
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, lip)
                .offset(y: travel * down)
        }
        .frame(height: height)
        .background(Color(hex: 0x060606))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
