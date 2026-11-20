import SwiftUI

/// A thin bar showing how far a playing tape has got.
struct TapeProgress: View {
    /// 0...1.
    let progress: CGFloat
    let track: Color

    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            track
            palette.accent
                .scaleEffect(x: min(max(progress, 0), 1), y: 1, anchor: .leading)
        }
        .accessibilityHidden(true)
    }
}
