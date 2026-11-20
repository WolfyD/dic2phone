import UIKit

/// The phone a tape was recorded on, as written in its metadata: "iPhone · iOS 18.2".
@MainActor
enum DeviceLabel {
    static var current: String {
        "\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)"
    }
}
