import SwiftUI

@main
struct Dic2PhoneApp: App {
    @State private var model = try? AppModel()

    var body: some Scene {
        WindowGroup {
            if let model {
                RootView(model: model)
            } else {
                StorageUnavailableView()
            }
        }
    }
}
