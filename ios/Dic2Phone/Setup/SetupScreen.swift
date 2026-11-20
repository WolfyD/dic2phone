import SwiftUI

/// The user's choices, in pages picked by a row of keys; the open page's key stays down.
struct SetupScreen: View {
    let navigate: (Screen) -> Void

    @Environment(\.palette) private var palette

    @State private var tab = SetupTab.look

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                DeckKey(label: String(localized: "\(Glyph.back) DECK"), height: 40) { navigate(.deck) }
                    .frame(width: 96)
                SectionTitle(text: String(localized: "SETUP"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            KeyBank(keys: SetupTab.allCases.map(tabKey), keyHeight: 40)
            ScrollView {
                page
                    .padding(.bottom, 12)
            }
            // A fresh scroll position for each page.
            .id(tab)
        }
        .padding([.horizontal, .top], 12)
    }

    private func tabKey(_ key: SetupTab) -> BankKey {
        let open = key == tab
        return BankKey(
            id: "\(key)",
            label: key.label,
            face: .glyph(open ? Glyph.chosen : Glyph.notChosen),
            labelColor: open ? palette.accent : nil,
            glyphColor: open ? palette.led : nil,
            latched: open,
            action: .tap { tab = key }
        )
    }

    @ViewBuilder
    private var page: some View {
        switch tab {
        case .look: LookTab()
        case .rec: RecTab()
        case .play: PlayTab()
        case .text: TextTab()
        case .more:
            VStack(spacing: 10) {
                AboutPanel()
                CreditsPanel()
            }
        }
    }
}
