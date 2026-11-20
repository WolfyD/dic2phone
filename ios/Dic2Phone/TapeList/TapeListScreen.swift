import SwiftUI

/// The deck's tapes in their carry case, or the shelf's in the rack. Tap plays, ⏏ loads into the
/// deck, a long press selects; the keys below act on the selection, or on every tape.
struct TapeListScreen: View {
    private static let noticeDuration: Duration = .seconds(3)

    let mode: TapeListMode
    let navigate: (Screen) -> Void

    @Environment(Settings.self) private var settings
    @Environment(TapeLibrary.self) private var library
    @Environment(Player.self) private var player
    @Environment(\.palette) private var palette

    @State private var selected: Set<TapeID> = []
    @State private var confirming: ConfirmRequest?
    @State private var sharing: [Tape] = []
    /// A short note after an action, standing in for Android's toasts.
    @State private var notice: String?

    var body: some View {
        let tapes = library.tapes(in: mode.rack, sortedBy: settings.sort(for: mode.rack))
        VStack(spacing: 10) {
            header(count: tapes.count, newCount: tapes.count(where: \.isNew))
            if !tapes.isEmpty {
                hintRow(count: tapes.count)
            }
            list(tapes)
                .frame(maxHeight: .infinity)
            if let playing = tapes.first(where: { $0.id == player.playingID }) {
                NowPlaying(tape: playing)
            }
            if let notice {
                Text(verbatim: notice)
                    .font(DeckFont.monoBold.fixed(12))
                    .foregroundStyle(palette.accent)
            }
            actionKeys(tapes)
        }
        .padding(12)
        // Leaving the list stops its tape, as on Android.
        .onDisappear(perform: player.stop)
        .task(id: notice) {
            guard notice != nil else { return }
            try? await Task.sleep(for: Self.noticeDuration)
            notice = nil
        }
        .alert(
            Text(verbatim: confirming?.title ?? ""),
            isPresented: Binding { confirming != nil } set: { if !$0 { confirming = nil } },
            presenting: confirming
        ) { request in
            Button(request.button, role: .destructive, action: request.action)
            Button("CANCEL", role: .cancel) {}
        } message: { request in
            Text(verbatim: request.message)
        }
        .sheet(isPresented: Binding { !sharing.isEmpty } set: { if !$0 { sharing = [] } }) {
            ShareSheet(files: library.fileURLs(of: sharing), onFinish: finishSharing)
                .presentationDetents([.medium, .large])
        }
    }

    private func header(count: Int, newCount: Int) -> some View {
        HStack(spacing: 12) {
            DeckKey(label: String(localized: "\(Glyph.back) DECK"), height: 40) { navigate(.deck) }
                .frame(width: 96)
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle(text: mode.title)
                Text(verbatim: subtitle(count: count, newCount: newCount))
                    .font(DeckFont.mono.fixed(11))
                    .foregroundStyle(palette.dim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func subtitle(count: Int, newCount: Int) -> String {
        switch mode.rack {
        case .deck: String(localized: "\(count) tapes · \(newCount) new")
        case .shelf: String(localized: "\(count) kept · Files › On My iPhone › Dic2Phone › Shelf")
        }
    }

    private func hintRow(count: Int) -> some View {
        let loading = mode == .load
        let hint = loading
            ? String(localized: "TAP A TAPE TO PUT IT IN")
            : String(localized: "TAP \(Glyph.play) PLAY · \(Glyph.eject) LOAD · HOLD SELECT")
        let sort = settings.sort(for: mode.rack)
        return HStack {
            Text(verbatim: hint)
                .font(loading ? DeckFont.monoBold.fixed(11) : DeckFont.mono.fixed(11))
                .foregroundStyle(loading ? palette.accent : palette.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            if count > 1 {
                DeckKey(label: "\(Glyph.sort) \(sort.label)", height: 32) { settings.cycleSort(for: mode.rack) }
                    .frame(width: 104)
                    .accessibilityLabel(Text("Sort: \(sort.label)"))
            }
        }
    }

    @ViewBuilder
    private func list(_ tapes: [Tape]) -> some View {
        if tapes.isEmpty {
            Text(verbatim: mode.emptyMessage)
                .font(DeckFont.mono.fixed(14))
                .foregroundStyle(palette.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if mode.rack == .deck {
            CarryCase {
                ForEach(tapes) { tape in
                    TapeCaseRow(tape: tape, state: rowState(of: tape), loadMode: mode == .load, actions: rowActions(for: tape))
                }
            }
        } else {
            ShelfRack {
                ForEach(tapes) { tape in
                    ShelfSpineRow(tape: tape, state: rowState(of: tape), actions: rowActions(for: tape))
                }
            }
        }
    }

    private func rowState(of tape: Tape) -> TapeRowState {
        let playing = player.playingID == tape.id
        let progress = playing && tape.durationMs > 0 ? CGFloat(player.positionMs) / CGFloat(tape.durationMs) : 0
        return TapeRowState(
            selected: selected.contains(tape.id),
            playing: playing,
            progress: progress,
            inDeck: player.loadedID == tape.id
        )
    }

    private func rowActions(for tape: Tape) -> TapeRowActions {
        TapeRowActions(
            tap: {
                if !selected.isEmpty {
                    toggleSelection(of: tape)
                } else if mode == .load {
                    putInDeck(tape)
                } else {
                    player.toggle(tape)
                }
            },
            select: { toggleSelection(of: tape) },
            load: { putInDeck(tape) }
        )
    }

    @ViewBuilder
    private func actionKeys(_ tapes: [Tape]) -> some View {
        let selection = tapes.filter { selected.contains($0.id) }
        if selection.isEmpty {
            wholeListKeys(tapes)
        } else {
            selectionKeys(selection)
        }
    }

    private func wholeListKeys(_ tapes: [Tape]) -> some View {
        KeyRow {
            DeckKey(label: String(localized: "SEND ALL")) { sharing = tapes }
            DeckKey(label: String(localized: "SELECT ALL")) { selected = Set(tapes.map(\.id)) }
            if mode.rack == .deck {
                DeckKey(label: String(localized: "ERASE ALL"), labelColor: palette.danger) { confirmEraseAll(tapes) }
            }
        }
        .disabled(tapes.isEmpty)
    }

    private func selectionKeys(_ selection: [Tape]) -> some View {
        VStack(spacing: 10) {
            if selection.count == 1, let tape = selection.first {
                KeyRow {
                    DeckKey(label: String(localized: "\(Glyph.eject) PUT IN DECK")) { putInDeck(tape) }
                }
            }
            KeyRow {
                DeckKey(label: String(localized: "SEND \(selection.count)")) { sharing = selection }
                DeckKey(label: Glyph.close) { selected = [] }
                    .layoutWeight(0.4)
                    .accessibilityLabel(Text("Clear selection"))
            }
            KeyRow {
                if mode.rack == .deck {
                    DeckKey(label: String(localized: "SHELVE")) { shelve(selection) }
                }
                DeckKey(label: String(localized: "ERASE"), labelColor: palette.danger) { confirmErase(selection) }
            }
        }
    }

    private func toggleSelection(of tape: Tape) {
        if selected.contains(tape.id) {
            selected.remove(tape.id)
        } else {
            selected.insert(tape.id)
        }
    }

    private func putInDeck(_ tape: Tape) {
        player.load(tape)
        selected = []
        navigate(.deck)
    }

    private func finishSharing(sent: Bool) {
        if sent, mode.rack == .deck {
            library.markHeard(sharing)
        }
        sharing = []
        selected = []
    }

    private func shelve(_ tapes: [Tape]) {
        stopIfPlaying(tapes)
        Task {
            let moved = await library.shelve(tapes)
            selected = []
            notice = moved == tapes.count
                ? String(localized: "Moved to shelf")
                : String(localized: "Moved \(moved) of \(tapes.count) to the shelf")
        }
    }

    private func confirmErase(_ tapes: [Tape]) {
        confirming = ConfirmRequest(
            title: String(localized: "Erase \(tapes.count) tapes?"),
            message: String(localized: "This can't be undone."),
            button: String(localized: "ERASE")
        ) { erase(tapes) }
    }

    private func confirmEraseAll(_ tapes: [Tape]) {
        confirming = ConfirmRequest(
            title: String(localized: "Erase the whole deck?"),
            message: String(localized: "All \(tapes.count) tapes on the deck will be deleted. Tapes on the shelf are kept."),
            button: String(localized: "ERASE ALL")
        ) { erase(tapes) }
    }

    private func erase(_ tapes: [Tape]) {
        stopIfPlaying(tapes)
        Task {
            let failures = await library.delete(tapes)
            selected = []
            if failures > 0 {
                notice = String(localized: "Couldn't erase \(failures) tapes")
            }
        }
    }

    private func stopIfPlaying(_ tapes: [Tape]) {
        if tapes.contains(where: { $0.id == player.playingID }) {
            player.stop()
        }
    }
}
