import SwiftUI

extension Color {
    /// Relative luminance, 0 for black to 1 for white, as Android's `Color.luminance()` gives it.
    var luminance: Double {
        let linear = resolve(in: EnvironmentValues())
        return 0.2126 * Double(linear.linearRed) + 0.7152 * Double(linear.linearGreen) + 0.0722 * Double(linear.linearBlue)
    }

    /// Mixed toward white channel by channel, the way the Android counter windows are lit.
    func lightened(by fraction: Double) -> Color {
        mix(with: .white, by: fraction, in: .device)
    }
}
