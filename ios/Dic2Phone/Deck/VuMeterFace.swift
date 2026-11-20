import SwiftUI

/// The meter drawn at one needle position. Being `Animatable`, it's redrawn at every in-between
/// position as the needle springs.
struct VuMeterFace: View, Animatable {
    var needle: CGFloat

    @Environment(\.palette) private var palette

    var animatableData: CGFloat {
        get { needle }
        set { needle = newValue }
    }

    var body: some View {
        let art = VuMeterArt(palette: palette, needle: needle)
        Canvas { context, size in
            art.draw(in: context, width: size.width)
        }
        .aspectRatio(VuMeterArt.ratio, contentMode: .fit)
    }
}
