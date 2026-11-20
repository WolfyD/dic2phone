import SwiftUI

/// A tape's captions as a list to read: tap a line to play from there, the one being spoken
/// stands out and stays in view.
struct TranscriptScreen: View {
    private static let noticeDuration: Duration = .seconds(3)

    let model: TranscriptModel

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 10) {
            header
            page
                .frame(maxHeight: .infinity)
            if let notice = model.notice {
                Text(verbatim: notice)
                    .font(DeckFont.monoBold.fixed(12))
                    .foregroundStyle(palette.accent)
            }
            keys
        }
        .padding(12)
        .task(id: model.tape) { await model.load() }
        .task(id: model.notice) {
            guard model.notice != nil else { return }
            try? await Task.sleep(for: Self.noticeDuration)
            model.notice = nil
        }
        .onChange(of: model.tapeIsGone) {
            if model.tapeIsGone { model.close() }
        }
        .alert(Text("Transcribe again?"), isPresented: Binding { model.confirmingRedo } set: { model.confirmingRedo = $0 }) {
            Button("REDO", action: model.redo)
            Button("CANCEL", role: .cancel) {}
        } message: {
            Text("Uses the model and language set in Setup. The current transcript is replaced when it's done.")
        }
        .sheet(isPresented: Binding { model.sharing != nil } set: { if !$0 { model.finishSharing() } }) {
            ShareSheet(items: model.sharing ?? []) { _ in model.finishSharing() }
                .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            DeckKey(label: String(localized: "\(Glyph.back) BACK"), height: 40, action: model.close)
                .frame(width: 104)
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle(text: String(localized: "TRANSCRIPT"))
                Text(verbatim: String(localized: "\(TapeNames.label(model.tape)) · tap a line to play"))
                    .font(DeckFont.mono.fixed(11))
                    .foregroundStyle(palette.dim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var page: some View {
        Group {
            if let transcript = model.transcript {
                if transcript.cues.isEmpty {
                    pageNote(String(localized: "No speech was found on this tape."))
                } else {
                    lines(transcript.cues)
                }
            } else {
                pageNote("…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.label, in: RoundedRectangle(cornerRadius: 6))
    }

    private func pageNote(_ text: String) -> some View {
        Text(verbatim: text)
            .font(DeckFont.mono.fixed(14))
            .foregroundStyle(palette.ink)
            .padding(12)
    }

    private func lines(_ cues: [Cue]) -> some View {
        let current = model.currentIndex
        return ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(cues.indices, id: \.self) { index in
                        TranscriptLine(cue: cues[index], isCurrent: index == current) { model.play(from: cues[index]) }
                            .id(index)
                    }
                }
            }
            .onChange(of: current) {
                guard let current else { return }
                withAnimation { scroller.scrollTo(current, anchor: UnitPoint(x: 0, y: 0.3)) }
            }
        }
    }

    private var keys: some View {
        VStack(spacing: 10) {
            if model.isPlaying {
                KeyRow {
                    DeckKey(label: String(localized: "\(Glyph.stop) STOP  \(TapeNames.duration(ms: model.positionMs))"), action: model.stop)
                }
            }
            KeyRow {
                DeckKey(label: String(localized: "COPY"), action: model.copy)
                    .disabled(!model.hasSpeech)
                DeckKey(label: String(localized: "SHARE"), action: model.sendText)
                    .disabled(!model.hasSpeech)
                DeckKey(label: ".SRT", action: model.sendCaptions)
                    .disabled(!model.hasSpeech)
                DeckKey(label: String(localized: "REDO")) { model.confirmingRedo = true }
            }
        }
    }
}
