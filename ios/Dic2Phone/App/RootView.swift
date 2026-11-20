import SwiftUI

/// The theme's backdrop with the current screen on it, and the app's services handed down to
/// every screen.
struct RootView: View {
    let model: AppModel

    @State private var screen = Screen.deck
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let settings = model.settings
        ZStack {
            DeckBackground(palette: settings.theme)
            current
        }
        .environment(\.palette, settings.theme)
        .environment(\.keyClick, model.keyClick)
        .environment(settings)
        .environment(model.library)
        .environment(model.recorder)
        .environment(model.player)
        .environment(model.flagKey)
        .preferredColorScheme(settings.theme.isLight ? .light : .dark)
        .task { await model.start() }
        .task { await model.stopForInterruptions() }
        // Tapes can arrive or leave through the Files app while Dic2Phone is in the background.
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task { await model.library.reload() }
            }
        }
        .onChange(of: settings.playSpeed) { model.player.applySpeed() }
        .onChange(of: settings.tapePitch) { model.player.applySpeed() }
    }

    @ViewBuilder
    private var current: some View {
        switch screen {
        case .deck: DeckScreen(navigate: navigate)
        case .tapes: TapeListScreen(mode: .deck, navigate: navigate)
        case .load: TapeListScreen(mode: .load, navigate: navigate)
        case .shelf: TapeListScreen(mode: .shelf, navigate: navigate)
        case .setup: SetupScreen(navigate: navigate)
        }
    }

    private func navigate(to next: Screen) {
        screen = next
    }
}
