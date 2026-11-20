import SwiftUI

/// TAPE INFO: what's written on a tape and what the deck knows about it. The title, notes, tags
/// and flag notes can be changed; the facts below them can't.
struct TapeInfoSheet: View {
    private static let factNameWidth: CGFloat = 96

    let tape: Tape
    let close: () -> Void

    @Environment(TapeLibrary.self) private var library
    @Environment(\.palette) private var palette

    @State private var meta: TapeMeta?
    @State private var draft: TapeInfoDraft?
    @State private var isSaving = false
    @State private var failed = false

    var body: some View {
        VStack(spacing: 12) {
            header
            if failed {
                Text("Couldn't save")
                    .font(DeckFont.monoBold.fixed(12))
                    .foregroundStyle(palette.accent)
            }
            ScrollView {
                content
                    .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(16)
        .presentationBackground(palette.panel)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            DeckKey(label: String(localized: "CANCEL"), height: 40, action: close)
                .frame(width: 104)
            SectionTitle(text: String(localized: "TAPE INFO"))
                .frame(maxWidth: .infinity)
            DeckKey(label: String(localized: "SAVE"), height: 40, labelColor: palette.accent) {
                Task { await save() }
            }
            .frame(width: 104)
            .disabled(draft == nil || isSaving)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let meta, let draft = Binding($draft) {
            VStack(alignment: .leading, spacing: 12) {
                fields(draft, flags: meta.flags)
                facts(meta)
            }
        } else {
            Text(verbatim: "…")
                .font(DeckFont.mono.fixed(14))
                .foregroundStyle(palette.dim)
        }
    }

    @ViewBuilder
    private func fields(_ draft: Binding<TapeInfoDraft>, flags: [Int64]) -> some View {
        let learnsWords = tape.rack != .vault
        TapeInfoField(
            label: String(localized: "TITLE (on the label)"),
            text: draft.title,
            limit: TapeMeta.titleLimit,
            placeholder: TapeNames.pretty(tape.id),
            learnsWords: learnsWords
        )
        TapeInfoField(
            label: String(localized: "NOTES"),
            text: draft.notes,
            limit: TapeMeta.notesLimit,
            multiline: true,
            learnsWords: learnsWords
        )
        TapeInfoField(
            label: String(localized: "TAGS (comma separated)"),
            text: draft.tags,
            limit: TapeInfoDraft.tagsInputLimit,
            placeholder: String(localized: "work, idea, song"),
            learnsWords: learnsWords
        )
        ForEach(flags, id: \.self) { flag in
            TapeInfoField(
                label: String(localized: "\(Glyph.flag) \(TapeNames.duration(ms: flag)) NOTE"),
                text: note(at: flag, in: draft),
                limit: TapeMeta.flagNoteLimit,
                learnsWords: learnsWords
            )
        }
    }

    private func note(at flag: Int64, in draft: Binding<TapeInfoDraft>) -> Binding<String> {
        Binding {
            draft.wrappedValue.flagNotes[flag] ?? ""
        } set: { note in
            draft.wrappedValue.flagNotes[flag] = note
        }
    }

    private func facts(_ meta: TapeMeta) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(TapeFacts.of(tape, meta: meta)) { fact in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(verbatim: fact.name)
                        .font(DeckFont.mono.fixed(11))
                        .foregroundStyle(palette.dim)
                        .frame(width: Self.factNameWidth, alignment: .leading)
                    Text(verbatim: fact.value)
                        .font(DeckFont.mono.fixed(12))
                        .foregroundStyle(palette.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, 6)
    }

    private func load() async {
        guard let meta = await library.meta(of: tape) else {
            close()
            return
        }
        self.meta = meta
        draft = TapeInfoDraft(meta: meta)
    }

    private func save() async {
        guard let draft else { return }
        isSaving = true
        defer { isSaving = false }
        if await library.saveInfo(draft, of: tape) {
            close()
        } else {
            failed = true
        }
    }
}
