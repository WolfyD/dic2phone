import SwiftUI

extension EnvironmentValues {
    /// Silent until the root view hands in the real one.
    @Entry var keyClick = KeyClick(play: {})
    /// The click of something hinged dropping into place, like the compartment's lid.
    @Entry var detentClick = KeyClick(play: {})
}
