import SwiftUI

extension EnvironmentValues {
    /// Silent until the root view hands in the real one.
    @Entry var keyClick = KeyClick(play: {})
}
