import SwiftUI

/// One speech model on Setup: whether it's downloaded, a key to use it, and its download.
struct SpeechModelRow: View {
    let model: SpeechModel

    @Environment(Settings.self) private var settings
    @Environment(CaptionQueue.self) private var captions
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                description
                    .frame(maxWidth: .infinity, alignment: .leading)
                DeckKey(label: useLabel, height: 40) { settings.speechModel = model }
                    .frame(width: 84)
                    .accessibilityAddTraits(inUse ? .isSelected : [])
            }
            if !isDownloaded {
                download
            }
        }
    }

    private var isDownloaded: Bool { captions.downloadedModels.contains(model) }
    private var inUse: Bool { settings.speechModel == model }

    private var useLabel: String {
        let use = String(localized: "USE")
        return inUse ? "\(Glyph.chosen) \(use)" : use
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Led(on: isDownloaded)
                Text(verbatim: model.name)
                    .font(DeckFont.monoBold.fixed(13))
                    .foregroundStyle(palette.text)
                if isDownloaded {
                    Text(verbatim: String(localized: "downloaded"))
                        .font(DeckFont.mono.fixed(12))
                        .foregroundStyle(palette.led)
                }
            }
            Text(verbatim: "\(model.sizeLabel) · \(model.note)")
                .font(DeckFont.mono.fixed(12))
                .foregroundStyle(palette.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var download: some View {
        if captions.waitingModels.contains(model) {
            HStack(spacing: 6) {
                Text(verbatim: downloadProgress)
                    .font(DeckFont.monoBold.fixed(12))
                    .foregroundStyle(palette.led)
                    .frame(maxWidth: .infinity, alignment: .leading)
                DeckKey(label: String(localized: "CANCEL"), height: 40, labelColor: palette.danger) {
                    captions.cancelAll()
                }
                .frame(width: 96)
            }
        } else {
            DeckKey(label: String(localized: "DOWNLOAD \(model.sizeLabel)"), height: 40) {
                captions.fetch(model)
            }
        }
    }

    private var downloadProgress: String {
        guard let status = captions.status, status.tape == nil, status.step == .fetching(model) else {
            return String(localized: "WAITING…")
        }
        return String(localized: "DOWNLOADING \(status.percent)%")
    }
}
