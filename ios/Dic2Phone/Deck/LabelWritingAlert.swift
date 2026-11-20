import SwiftUI

/// "Write on the label", or on a flag: a one-line text field in an alert, cut off at `limit`
/// letters.
struct LabelWritingAlert: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let original: String
    let placeholder: String
    let limit: Int
    let hint: String
    /// Off for vault tapes, so what's written on them stays out of the keyboard's learned words.
    let learnsWords: Bool
    let onWrite: (String) -> Void

    @State private var draft = ""

    /// The title for writing on what's in the deck, or on a tape's label.
    static func labelTitle(minidisc: Bool) -> String {
        minidisc ? String(localized: "TITLE THE DISC") : String(localized: "WRITE ON THE LABEL")
    }

    func body(content: Content) -> some View {
        content
            .alert(Text(verbatim: title), isPresented: $isPresented) {
                TextField(placeholder, text: $draft)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(!learnsWords)
                    .onChange(of: draft) { _, text in
                        if text.count > limit { draft = String(text.prefix(limit)) }
                    }
                Button("WRITE") { onWrite(draft) }
                Button("CANCEL", role: .cancel) {}
            } message: {
                Text(verbatim: hint)
            }
            .onChange(of: isPresented) { _, shown in
                if shown { draft = original }
            }
    }
}

extension View {
    func labelWritingAlert(
        isPresented: Binding<Bool>,
        title: String,
        original: String,
        placeholder: String,
        limit: Int,
        hint: String,
        learnsWords: Bool = true,
        onWrite: @escaping (String) -> Void
    ) -> some View {
        modifier(LabelWritingAlert(
            isPresented: isPresented, title: title, original: original, placeholder: placeholder,
            limit: limit, hint: hint, learnsWords: learnsWords, onWrite: onWrite
        ))
    }
}
