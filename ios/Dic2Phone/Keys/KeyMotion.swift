import SwiftUI

enum KeyMotion {
    /// Quick, hard travel with a tiny bounce at the bottom; the key comes back up a little slower.
    /// The same springs as the Android keys (stiffness 3000 down, 1400 up, damping 0.55).
    static func spring(pressed: Bool) -> Animation {
        .spring(response: pressed ? 0.115 : 0.168, dampingFraction: 0.55)
    }
}
