import SwiftUI

/// A round lamp: the REC lamp, and CUE's smaller one.
struct Led: View {
    let on: Bool
    var diameter: CGFloat = 14

    @Environment(\.palette) private var palette

    var body: some View {
        Circle()
            .fill(RadialGradient(
                colors: on ? [.white.opacity(0.8), palette.led] : [palette.ledOff, .black.opacity(0.8)],
                center: .center, startRadius: 0, endRadius: diameter / 2
            ))
            .overlay(Circle().strokeBorder(.black, lineWidth: 1))
            .frame(width: diameter, height: diameter)
            .shadow(color: on ? palette.led : .clear, radius: on ? 4 : 0)
            .accessibilityHidden(true)
    }
}
