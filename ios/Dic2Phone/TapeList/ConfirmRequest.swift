import Foundation

/// A destructive action waiting for the user to say yes.
struct ConfirmRequest {
    let title: String
    let message: String
    let button: String
    let action: () -> Void
}
