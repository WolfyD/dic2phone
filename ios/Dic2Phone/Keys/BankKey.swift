import SwiftUI

/// One key of a key bank, its label printed on the faceplate above it.
struct BankKey: Identifiable {
    /// Stays the same when the label changes, so a press in progress survives it.
    let id: String
    let label: String
    let face: KeyFace
    var weight: CGFloat = 1
    var labelColor: Color?
    var face1: Color?
    var face2: Color?
    var glyphColor: Color?
    var latched = false
    let action: KeyAction
}
