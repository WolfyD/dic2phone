import SwiftUI

/// A search box over the transcripts, the places the words were said, and the tape playing
/// from one of them.
struct SearchScreen: View {
    @State private var model: SearchModel

    @Environment(\.palette) private var palette

    init(model: SearchModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            field
            results
                .frame(maxHeight: .infinity)
            if let playing = model.playing {
                SearchPlaying(tape: playing.tape, transcript: playing.transcript)
            }
        }
        .padding(12)
        .task(id: model.transcribedTapes.map(\.id)) { await model.readTranscripts() }
        .onDisappear(perform: model.leave)
    }

    private var header: some View {
        HStack(spacing: 12) {
            DeckKey(label: String(localized: "\(Glyph.back) BACK"), height: 40, action: model.goBack)
                .frame(width: 104)
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle(text: String(localized: "SEARCH TAPES"))
                Text(verbatim: subtitle)
                    .font(DeckFont.mono.fixed(11))
                    .foregroundStyle(palette.dim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var subtitle: String {
        guard !model.isReading else { return String(localized: "reading transcripts…") }
        let count = String(localized: "\(model.transcribedTapes.count) transcribed tapes")
        return model.vaultIsLocked ? count + " · " + String(localized: "vault locked, not searched") : count
    }

    private var field: some View {
        TextField("", text: $model.query, prompt: Text("a word or phrase").foregroundStyle(palette.dim))
            .font(DeckFont.mono.fixed(16))
            .foregroundStyle(palette.text)
            .tint(palette.accent)
            // Keeps what's said on the tapes out of the keyboard's learned words.
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            .padding(.horizontal, 12)
            .frame(height: 48)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.dim, lineWidth: 1))
    }

    @ViewBuilder
    private var results: some View {
        let hits = model.hits
        if !model.isReading && model.transcribedTapes.isEmpty {
            hint(String(localized: "No transcripts yet.\nSelect tapes and press TEXT to make them."))
        } else if model.query.allSatisfy(\.isWhitespace) {
            hint(String(localized: "Type to search what was said on your tapes."))
        } else if hits.isEmpty && !model.isReading {
            hint(String(localized: "Not found."))
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(hits.indices, id: \.self) { index in
                        SearchHitRow(hit: hits[index]) { model.play(hits[index]) }
                    }
                }
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(verbatim: text)
            .font(DeckFont.mono.fixed(14))
            .foregroundStyle(palette.dim)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
