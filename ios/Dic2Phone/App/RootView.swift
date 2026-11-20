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
        .environment(\.detentClick, model.detentClick)
        .environment(settings)
        .environment(model.library)
        .environment(model.recorder)
        .environment(model.player)
        .environment(model.flagKey)
        .environment(model.vault)
        .environment(model.captions)
        .preferredColorScheme(settings.theme.isLight ? .light : .dark)
        .task { await model.start() }
        .task { await model.stopForInterruptions() }
        .onChange(of: scenePhase) { sceneChanged() }
        .onChange(of: settings.playSpeed) { model.player.applySpeed() }
        .onChange(of: settings.tapePitch) { model.player.applySpeed() }
    }

    @ViewBuilder
    private var current: some View {
        switch screen {
        case .deck: DeckScreen(navigate: navigate)
        case .tapes: tapeList(.deck)
        case .load: tapeList(.load)
        case .shelf: tapeList(.shelf)
        case .vault: tapeList(.vault)
        case .setup: SetupScreen(navigate: navigate)
        case .search(let back): search(returningTo: back)
        }
    }

    private func tapeList(_ mode: TapeListMode) -> TapeListScreen {
        TapeListScreen(model: TapeListModel(
            mode: mode,
            settings: model.settings,
            library: model.library,
            player: model.player,
            vault: model.vault,
            captions: model.captions,
            navigate: navigate
        ))
    }

    private func search(returningTo back: Screen) -> SearchScreen {
        SearchScreen(model: SearchModel(library: model.library, player: model.player, vault: model.vault) {
            navigate(to: back)
        })
    }

    /// Leaving locks the vault; not just going inactive, which the Face ID sheet does.
    private func sceneChanged() {
        switch scenePhase {
        case .active:
            model.appBecameActive()
        case .background:
            Task { await model.vault.lock() }
        default:
            break
        }
    }

    private func navigate(to next: Screen) {
        screen = next
    }
}
