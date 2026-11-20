import SwiftUI

extension EnvironmentValues {
    /// The current deck theme; the root view sets it from Settings.
    @Entry var palette: Palette = Themes.walnut
}
