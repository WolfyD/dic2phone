import SwiftUI
import UIKit

/// The system share sheet, for tape files or a transcript. SwiftUI's ShareLink can't be opened
/// from a key, and doesn't say whether anything was sent.
struct ShareSheet: UIViewControllerRepresentable {
    /// File URLs or text.
    let items: [Any]
    let onFinish: (_ sent: Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, sent, _, _ in onFinish(sent) }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
