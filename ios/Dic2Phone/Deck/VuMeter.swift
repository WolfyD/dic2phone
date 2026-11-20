import SwiftUI

/// The VU meter. The needle swings to the level on a loose spring, overshooting a little like a
/// real one.
struct VuMeter: View {
    /// 0...1.
    let level: Float

    var body: some View {
        VuMeterFace(needle: CGFloat(level))
            .animation(.spring(response: 0.39, dampingFraction: 0.55), value: level)
            .accessibilityHidden(true)
    }
}
