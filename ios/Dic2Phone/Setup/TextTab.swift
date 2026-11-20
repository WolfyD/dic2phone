import SwiftUI

/// Transcripts: the language, whether new tapes get them by themselves, and the speech models.
struct TextTab: View {
    @Environment(Settings.self) private var settings
    @Environment(CaptionQueue.self) private var captions
    @Environment(\.palette) private var palette

    @State private var modelsDeleted = false

    var body: some View {
        SetupPanel(title: String(localized: "TRANSCRIPTS")) {
            SetupHelp(text: String(localized: "Select tapes and press TEXT (or TRANSCRIBE on the deck) to turn speech into text: subtitles while playing, a transcript to read or send, .srt files, and search across all tapes. It all runs on the phone; only the speech model is downloaded, once."))
            language
            autoTranscribe
            SetupHeading(text: String(localized: "MODEL"))
            ForEach(SpeechModel.allCases, id: \.self) { model in
                SpeechModelRow(model: model)
            }
            if let error = captions.lastError {
                Text(verbatim: "\(Glyph.warning) \(error)")
                    .font(DeckFont.mono.fixed(12))
                    .foregroundStyle(palette.accent)
            }
            SetupHelp(text: String(localized: "Models come from Hugging Face (huggingface.co) once, then everything runs offline. Use Wi-Fi for the bigger one."))
            deleteModels
        }
    }

    @ViewBuilder
    private var language: some View {
        SetupHeading(text: String(localized: "LANGUAGE"))
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(CaptionLanguage.codes, id: \.self) { code in
                    languageKey(code)
                }
            }
        }
        SetupHelp(text: String(localized: "AUTO guesses per tape. Picking the language is more reliable for short tapes."))
    }

    private func languageKey(_ code: String) -> some View {
        let label = CaptionLanguage.label(code)
        let chosen = code == settings.captionLanguage
        return DeckKey(label: chosen ? "\(Glyph.chosen) \(label)" : label, height: 40) {
            settings.captionLanguage = code
        }
        .frame(width: code == CaptionLanguage.automatic ? 84 : 60)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    @ViewBuilder
    private var autoTranscribe: some View {
        SetupHeading(text: String(localized: "AUTO TRANSCRIBE"))
        ChoiceKeys(
            labels: AutoCaptions.allCases.map(\.label),
            chosen: AutoCaptions.allCases.firstIndex(of: settings.autoCaptions) ?? 0
        ) { settings.autoCaptions = AutoCaptions.allCases[$0] }
        SetupHelp(text: String(localized: "Transcribe new tapes by themselves, right after recording. A tape recorded while the phone is locked is done once you unlock it and open Dic2Phone."))
        if settings.autoCaptions != .off, !hasModelInUse {
            Text(verbatim: String(localized: "Download and USE a model below first."))
                .font(DeckFont.mono.fixed(12))
                .foregroundStyle(palette.accent)
        }
    }

    private var hasModelInUse: Bool {
        settings.speechModel.map(captions.downloadedModels.contains) ?? false
    }

    @ViewBuilder
    private var deleteModels: some View {
        DeckKey(label: String(localized: "DELETE MODELS"), height: 40, labelColor: palette.danger) {
            captions.deleteModels()
            modelsDeleted = true
        }
        .disabled(captions.downloadedModels.isEmpty || captions.isBusy)
        if modelsDeleted {
            SetupHelp(text: String(localized: "Models deleted. Transcripts you made are kept."))
        }
    }
}
