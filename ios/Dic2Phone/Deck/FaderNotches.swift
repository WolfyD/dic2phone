import CoreGraphics

/// Where a fader's notches sit across its width, inset so the knob fits at either end.
struct FaderNotches {
    static let inset: CGFloat = 14

    let width: CGFloat
    let count: Int

    var step: CGFloat {
        count > 1 ? max(width - 2 * Self.inset, 1) / CGFloat(count - 1) : 1
    }

    func x(of notch: CGFloat) -> CGFloat {
        Self.inset + notch * step
    }

    func nearest(to x: CGFloat) -> Int {
        min(max(Int(((x - Self.inset) / step).rounded()), 0), max(count - 1, 0))
    }
}
