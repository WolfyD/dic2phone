import SwiftUI

/// The deck's tapes in their carry case, the shelf's in the wooden rack, or the vault's in the
/// steel one. Tap plays, ⏏ loads into the deck, a long press selects; the keys below act on the
/// selection, or on every tape.
struct TapeListScreen: View {
    private static let noticeDuration: Duration = .seconds(3)

    @State private var model: TapeListModel

    @Environment(Player.self) private var player
    @Environment(\.palette) private var palette

    init(model: TapeListModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            if let reading = model.reading {
                TranscriptScreen(model: reading)
            } else {
                tapesView
            }
        }
        .onDisappear(perform: model.leave)
        .transcribeRequest($model.transcribing)
    }

    private var tapesView: some View {
        let tapes = model.tapes
        return VStack(spacing: 10) {
            header(tapes)
            if !tapes.isEmpty {
                hintRow(count: tapes.count)
            }
            list(tapes)
                .frame(maxHeight: .infinity)
            if let playing = tapes.first(where: { $0.id == player.playingID }) {
                NowPlaying(tape: playing) { model.read(playing) }
            }
            CaptionStatusStrip()
            if model.mode == .shelf {
                VaultBar(isOpen: model.vaultIsOpen, count: model.vaultCount, action: model.openVaultScreen)
            }
            if let notice = model.notice {
                Text(verbatim: notice)
                    .font(DeckFont.monoBold.fixed(12))
                    .foregroundStyle(palette.accent)
            }
            TapeListKeys(model: model)
        }
        .padding(12)
        .task(id: model.notice) {
            guard model.notice != nil else { return }
            try? await Task.sleep(for: Self.noticeDuration)
            model.notice = nil
        }
        .alert(
            Text(verbatim: model.confirming?.title ?? ""),
            isPresented: Binding { model.confirming != nil } set: { if !$0 { model.confirming = nil } },
            presenting: model.confirming
        ) { request in
            Button(request.button, role: .destructive, action: request.action)
            Button("CANCEL", role: .cancel) {}
        } message: { request in
            Text(verbatim: request.message)
        }
        .sheet(isPresented: Binding { model.sharing != nil } set: { if !$0 { model.finishSharing(sent: false) } }) {
            ShareSheet(items: model.sharing?.files ?? [], onFinish: model.finishSharing)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $model.info, onDismiss: model.clearSelection) { tape in
            TapeInfoSheet(tape: tape) { model.info = nil }
        }
    }

    private func header(_ tapes: [Tape]) -> some View {
        HStack(spacing: 12) {
            DeckKey(label: model.mode.backLabel, height: 40, action: model.goBack)
                .frame(width: 104)
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle(text: model.mode.title)
                Text(verbatim: subtitle(tapes))
                    .font(DeckFont.mono.fixed(11))
                    .foregroundStyle(palette.dim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DeckKey(label: Glyph.search, height: 40, action: model.openSearch)
                .frame(width: 48)
                .accessibilityLabel(Text("Search transcripts"))
        }
    }

    private func subtitle(_ tapes: [Tape]) -> String {
        switch model.mode.rack {
        case .deck:
            String(localized: "\(tapes.count) tapes · \(tapes.count(where: \.isNew)) new")
        case .shelf:
            String(localized: "\(tapes.count) kept · Files › On My iPhone › Dic2Phone › Shelf")
        case .vault:
            model.isLocked
                ? String(localized: "locked · encrypted on this phone")
                : String(localized: "\(tapes.count) locked away · open")
        }
    }

    private func hintRow(count: Int) -> some View {
        let loading = model.mode == .load
        let hint = loading
            ? String(localized: "TAP A TAPE TO PUT IT IN")
            : String(localized: "TAP \(Glyph.play) PLAY · \(Glyph.eject) LOAD · HOLD SELECT")
        let sort = model.sort
        return HStack {
            Text(verbatim: hint)
                .font(loading ? DeckFont.monoBold.fixed(11) : DeckFont.mono.fixed(11))
                .foregroundStyle(loading ? palette.accent : palette.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            if count > 1 {
                DeckKey(label: "\(Glyph.sort) \(sort.label)", height: 32, action: model.cycleSort)
                    .frame(width: 104)
                    .accessibilityLabel(Text("Sort: \(sort.label)"))
            }
        }
    }

    @ViewBuilder
    private func list(_ tapes: [Tape]) -> some View {
        if model.isLocked {
            VaultDoor(
                isKeyLost: model.isKeyLost,
                passcodeIsSet: model.passcodeIsSet,
                unlock: model.unlock,
                reset: model.confirmReset
            )
        } else if tapes.isEmpty {
            Text(verbatim: model.mode.emptyMessage)
                .font(DeckFont.mono.fixed(14))
                .foregroundStyle(palette.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            rack(tapes)
        }
    }

    @ViewBuilder
    private func rack(_ tapes: [Tape]) -> some View {
        let waiting = model.waitingForTranscripts
        switch model.mode.rack {
        case .deck:
            CarryCase {
                ForEach(tapes) { tape in
                    TapeCaseRow(
                        tape: tape,
                        state: rowState(of: tape, waiting: waiting),
                        loadMode: model.mode == .load,
                        actions: rowActions(for: tape)
                    )
                }
            }
        case .shelf, .vault:
            ShelfRack(material: model.mode.rack == .vault ? .steel : .wood) {
                ForEach(tapes) { tape in
                    ShelfSpineRow(tape: tape, state: rowState(of: tape, waiting: waiting), actions: rowActions(for: tape))
                }
            }
        }
    }

    private func rowState(of tape: Tape, waiting: Set<TapeID>) -> TapeRowState {
        let playing = player.playingID == tape.id
        let progress = playing && tape.durationMs > 0 ? CGFloat(player.positionMs) / CGFloat(tape.durationMs) : 0
        return TapeRowState(
            selected: model.selected.contains(tape.id),
            playing: playing,
            progress: progress,
            inDeck: player.loadedID == tape.id,
            transcribing: waiting.contains(tape.id)
        )
    }

    private func rowActions(for tape: Tape) -> TapeRowActions {
        TapeRowActions(
            tap: { model.tap(tape) },
            select: { model.toggleSelection(of: tape) },
            load: { model.putInDeck(tape) }
        )
    }
}
