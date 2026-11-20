import SwiftUI

/// The round REC lamp.
struct Led: View {
    private static let diameter: CGFloat = 14

    let on: Bool

    @Environment(\.palette) private var palette

    var body: some View {
        Circle()
            .fill(RadialGradient(
                colors: on ? [.white.opacity(0.8), palette.led] : [palette.ledOff, .black.opacity(0.8)],
                center: .center, startRadius: 0, endRadius: Self.diameter / 2
            ))
            .overlay(Circle().strokeBorder(.black, lineWidth: 1))
            .frame(width: Self.diameter, height: Self.diameter)
            .shadow(color: on ? palette.led : .clear, radius: on ? 4 : 0)
            .accessibilityHidden(true)
    }
}
