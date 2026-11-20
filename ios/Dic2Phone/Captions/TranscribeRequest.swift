import SwiftUI

/// Queues tapes asked to be transcribed, first asking which speech model to download if none
/// has been picked yet.
struct TranscribeRequest: ViewModifier {
    @Binding var tapes: [Tape]?

    @Environment(Settings.self) private var settings
    @Environment(CaptionQueue.self) private var captions

    func body(content: Content) -> some View {
        content
            .alert(Text("PICK A SPEECH MODEL"), isPresented: choosingModel) {
                ForEach(SpeechModel.allCases, id: \.self) { model in
                    Button(String(localized: "\(model.name) · \(model.sizeLabel)")) { pick(model) }
                }
                Button("CANCEL", role: .cancel) {}
            } message: {
                Text("Transcripts are made on the phone, nothing is uploaded. The model is downloaded once (Wi-Fi recommended). BASE is quick, fine for clear English; SMALL is slower, much better for other languages. You can switch later in Setup.")
            }
            .onChange(of: tapes) {
                if settings.speechModel != nil { queue() }
            }
    }

    private var choosingModel: Binding<Bool> {
        Binding(
            get: { tapes != nil && settings.speechModel == nil },
            set: { shown in if !shown { tapes = nil } }
        )
    }

    private func pick(_ model: SpeechModel) {
        settings.speechModel = model
        queue()
    }

    private func queue() {
        guard let tapes else { return }
        captions.transcribe(tapes)
        self.tapes = nil
    }
}

extension View {
    func transcribeRequest(_ tapes: Binding<[Tape]?>) -> some View {
        modifier(TranscribeRequest(tapes: tapes))
    }
}
