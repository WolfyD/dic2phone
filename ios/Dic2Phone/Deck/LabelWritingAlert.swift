import SwiftUI

/// "Write on the label": a one-line text field in an alert, cut off at `limit` letters.
struct LabelWritingAlert: ViewModifier {
    @Binding var isPresented: Bool
    let original: String
    let placeholder: String
    let limit: Int
    let hint: String
    let onWrite: (String) -> Void

    @State private var draft = ""

    func body(content: Content) -> some View {
        content
            .alert(Text("WRITE ON THE LABEL"), isPresented: $isPresented) {
                TextField(placeholder, text: $draft)
                    .textInputAutocapitalization(.sentences)
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
        original: String,
        placeholder: String,
        limit: Int,
        hint: String,
        onWrite: @escaping (String) -> Void
    ) -> some View {
        modifier(LabelWritingAlert(
            isPresented: isPresented, original: original, placeholder: placeholder,
            limit: limit, hint: hint, onWrite: onWrite
        ))
    }
}
