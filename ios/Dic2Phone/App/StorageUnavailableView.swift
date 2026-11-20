import SwiftUI

/// Shown instead of the deck when the app can't make its tape folders, so it never records
/// tapes it can't keep.
struct StorageUnavailableView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text(verbatim: Glyph.warning)
                .font(.largeTitle)
            Text("Dic2Phone can't open its tape storage.")
                .font(.headline)
            Text("Check that the iPhone has free space, then open the app again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(32)
    }
}
