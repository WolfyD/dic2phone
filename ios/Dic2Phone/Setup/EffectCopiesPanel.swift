import SwiftUI

/// EFFECT COPIES: how many tapes have one and the space they take, how long one is kept
/// without being played, and a key to delete them all.
struct EffectCopiesPanel: View {
    /// Copies are made in the background, so the count is read again while the panel shows.
    private static let refreshInterval: Duration = .seconds(5)

    @Environment(Settings.self) private var settings
    @Environment(TapeLibrary.self) private var library
    @Environment(\.palette) private var palette

    var body: some View {
        let usage = library.effectCopyUsage
        SetupPanel(title: String(localized: "EFFECT COPIES")) {
            Text(verbatim: String(localized: "\(usage.count) ready · \(usage.bytes.formatted(.byteCount(style: .file)))"))
                .font(DeckFont.monoBold.fixed(12))
                .foregroundStyle(palette.led)
            SetupHelp(text: String(localized: "A tape's copy with the effects baked in is made when it goes into the deck or is first played with PLAY WITH EFFECTS on, or when it's sent WITH TAPE SOUND. It's kept so the tape isn't dubbed again, and goes when the tape does. iPhone may also clear copies when storage runs low; they're made again when needed."))
            SetupHeading(text: String(localized: "DELETE IF NOT PLAYED FOR"))
            ChoiceKeys(days: EffectCopies.keepChoices, chosen: settings.effectKeepDays) { settings.effectKeepDays = $0 }
            DeckKey(label: String(localized: "CLEAR NOW"), height: 40, labelColor: palette.danger) {
                Task { await library.clearEffectCopies() }
            }
            .disabled(usage.count == 0)
        }
        .task {
            repeat {
                await library.refreshEffectCopyUsage()
            } while (try? await Task.sleep(for: Self.refreshInterval)) != nil
        }
        .onChange(of: settings.effectKeepDays) {
            Task {
                await library.tidyEffectCopies(unplayedDays: settings.effectKeepDays)
                await library.refreshEffectCopyUsage()
            }
        }
    }
}
