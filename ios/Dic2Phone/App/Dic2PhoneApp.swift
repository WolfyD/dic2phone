import AppIntents
import SwiftUI

@main
struct Dic2PhoneApp: App {
    @State private var model: AppModel?

    /// The shortcuts in `Shortcuts/` are run by the system, which hands them the recorder from here.
    init() {
        let model = try? AppModel()
        _model = State(initialValue: model)
        AppDependencyManager.shared.add(dependency: model?.recorder)
    }

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
