import SwiftUI

/// The tape counter's little square plastic reset button, sinking into its hole when pressed.
struct CounterResetStyle: ButtonStyle {
    let palette: Palette

    func makeBody(configuration: Configuration) -> some View {
        let down: CGFloat = configuration.isPressed ? 1 : 0
        let cap = RoundedRectangle(cornerRadius: 3)
        cap.fill(Color(hex: 0x050505))
            .frame(width: 28, height: 28)
            .overlay {
                cap.fill(LinearGradient(
                    colors: [palette.key1.mix(with: .white, by: 0.15), palette.key2],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .overlay(cap.strokeBorder(.black.opacity(0.6), lineWidth: 1))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(palette.key1.mix(with: palette.key2, by: 0.35 + 0.25 * down))
                        .padding(4)
                )
                .frame(width: 24, height: 24)
                .shadow(color: .black.opacity(0.5), radius: 3 * (1 - down), y: 1 - down)
                .offset(x: 1.5 * down, y: 2 * down)
            }
            .animation(KeyMotion.spring(pressed: configuration.isPressed), value: configuration.isPressed)
    }
}
