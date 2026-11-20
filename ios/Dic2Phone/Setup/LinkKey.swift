import SwiftUI

/// A key that opens a web page in the browser.
struct LinkKey: View {
    let label: String
    let url: URL?

    @Environment(\.openURL) private var openURL

    var body: some View {
        DeckKey(label: "\(label) ↗", height: 40) {
            if let url { openURL(url) }
        }
        .disabled(url == nil)
        .accessibilityAddTraits(.isLink)
    }
}
