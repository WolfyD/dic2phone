import SwiftUI

/// Asks whether tapes go as recorded or with the TAPE EFFECTS baked into the copies sent; with
/// no effects turned on, offers the way to Setup instead.
struct SendChoice: ViewModifier {
    let model: TapeListModel

    func body(content: Content) -> some View {
        content
            .alert(
                Text("Send \(model.choosingSend?.count ?? 0) tapes"),
                isPresented: Binding { model.choosingSend != nil } set: { if !$0 { model.choosingSend = nil } },
                presenting: model.choosingSend
            ) { tapes in
                Button("AS RECORDED") { model.sendAsRecorded(tapes) }
                if model.effectsAreOn {
                    Button("WITH TAPE SOUND") { model.sendWithTapeSound(tapes) }
                } else {
                    Button("OPEN SETUP ▶", action: model.openEffectsSetup)
                }
                Button("CANCEL", role: .cancel) {}
            } message: { _ in
                if model.effectsAreOn {
                    Text("AS RECORDED: exactly what the mic heard.\nWITH TAPE SOUND: a copy with hiss, wobble and old-recorder tone baked in. Your tape stays clean.")
                } else {
                    Text("AS RECORDED: exactly what the mic heard.\nTo send with tape sound, turn on some TAPE EFFECTS in Setup → PLAY first.")
                }
            }
    }
}

extension View {
    func sendChoice(_ model: TapeListModel) -> some View {
        modifier(SendChoice(model: model))
    }
}
