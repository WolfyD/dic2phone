import SwiftUI

/// The keys under a tape list: for every tape, or for the selected ones once there are any.
/// While a long job runs they give way to a lit lamp and what it's doing.
struct TapeListKeys: View {
    let model: TapeListModel

    @Environment(\.palette) private var palette

    var body: some View {
        if let busy = model.busy {
            busyRow(busy)
        } else if !model.isLocked {
            let selection = model.selection
            if selection.isEmpty {
                wholeListKeys(model.tapes)
            } else {
                selectionKeys(selection)
            }
        }
    }

    private func busyRow(_ busy: String) -> some View {
        HStack(spacing: 10) {
            Led(on: true)
            Text(verbatim: busy)
                .font(DeckFont.monoBold.fixed(13))
                .foregroundStyle(palette.accent)
        }
        .frame(height: 52)
    }

    @ViewBuilder
    private func wholeListKeys(_ tapes: [Tape]) -> some View {
        KeyRow {
            DeckKey(label: String(localized: "SEND ALL")) { model.send(tapes) }
                .disabled(tapes.isEmpty)
            DeckKey(label: String(localized: "SELECT ALL"), action: model.selectAll)
                .disabled(tapes.isEmpty)
            switch model.mode.rack {
            case .deck:
                DeckKey(label: String(localized: "ERASE ALL"), labelColor: palette.danger) { model.confirmEraseAll(tapes) }
                    .disabled(tapes.isEmpty)
            case .vault:
                DeckKey(label: String(localized: "\(Glyph.locked) LOCK"), action: model.lock)
            case .shelf:
                EmptyView()
            }
        }
    }

    private func selectionKeys(_ selection: [Tape]) -> some View {
        VStack(spacing: 10) {
            if selection.count == 1, let tape = selection.first {
                KeyRow {
                    DeckKey(label: String(localized: "\(Glyph.eject) PUT IN DECK")) { model.putInDeck(tape) }
                }
            }
            KeyRow {
                DeckKey(label: String(localized: "SEND \(selection.count)")) { model.send(selection) }
                DeckKey(label: Glyph.close, action: model.clearSelection)
                    .layoutWeight(0.4)
                    .accessibilityLabel(Text("Clear selection"))
            }
            KeyRow {
                rackKeys(selection)
                DeckKey(label: String(localized: "ERASE"), labelColor: palette.danger) { model.confirmErase(selection) }
            }
        }
    }

    @ViewBuilder
    private func rackKeys(_ selection: [Tape]) -> some View {
        switch model.mode.rack {
        case .deck:
            DeckKey(label: String(localized: "SHELVE")) { model.shelve(selection) }
            lockKey(selection)
        case .shelf:
            lockKey(selection)
        case .vault:
            DeckKey(label: String(localized: "TAKE OUT")) { model.confirmTakeOut(selection) }
        }
    }

    private func lockKey(_ selection: [Tape]) -> some View {
        DeckKey(label: String(localized: "\(Glyph.locked) LOCK")) { model.lockAway(selection) }
    }
}
