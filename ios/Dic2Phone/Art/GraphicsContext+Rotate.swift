import SwiftUI

extension GraphicsContext {
    /// Turns everything drawn afterwards around `point`, like Android's `rotate(degrees, px, py)`.
    mutating func rotate(by angle: Angle, around point: CGPoint) {
        translateBy(x: point.x, y: point.y)
        rotate(by: angle)
        translateBy(x: -point.x, y: -point.y)
    }
}
