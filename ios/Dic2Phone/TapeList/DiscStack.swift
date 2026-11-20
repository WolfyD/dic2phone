import SwiftUI

/// MINIDISC mode's tape lists: the discs lie stacked with only their top edges showing, in a case
/// for the deck's, between wooden or steel rails for the shelf's and the vault's. A tap pulls a
/// disc out; a second tap plays it. While tapes are selected, a tap selects instead.
struct DiscStack: View {
    /// Long enough for the pulled-out disc to finish growing before it's scrolled into view.
    private static let scrollDelay: Duration = .milliseconds(280)

    let tapes: [Tape]
    let rack: Rack
    let loadMode: Bool
    let selecting: Bool
    let state: (Tape) -> TapeRowState
    let actions: (Tape) -> TapeRowActions

    @State private var lifted: TapeID?
    @Environment(\.keyClick) private var keyClick

    var body: some View {
        HStack(spacing: 0) {
            rail
            GeometryReader { geometry in
                stack(discHeight: min(max(geometry.size.width * 0.6, 170), 240))
            }
            rail
        }
        .background(LinearGradient(colors: backColors, startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(border, lineWidth: 2))
    }

    private func stack(discHeight: CGFloat) -> some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(tapes.enumerated()), id: \.element.id) { index, tape in
                        disc(tape, height: discHeight)
                            .zIndex(Double(index))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, discHeight - StackedDisc.strip + 10)
            }
            .task(id: lifted) {
                guard let lifted else { return }
                do {
                    try await Task.sleep(for: Self.scrollDelay)
                } catch {
                    return
                }
                withAnimation { scroller.scrollTo(lifted) }
            }
        }
    }

    /// Each disc takes up only its strip, so the next one covers the rest; a pulled-out disc
    /// takes its full height and lifts a little off the stack.
    private func disc(_ tape: Tape, height: CGFloat) -> some View {
        let up = lifted == tape.id
        return StackedDisc(
            tape: tape, state: state(tape), lifted: up, loadMode: loadMode, height: height,
            tap: { tapDisc(tape) }, actions: actions(tape)
        )
        .offset(x: up ? -4 : 0, y: up ? -6 : 0)
        .shadow(color: .black.opacity(up ? 0.5 : 0), radius: 8, y: 4)
        .frame(height: up ? height + 10 : StackedDisc.strip, alignment: .top)
        .id(tape.id)
    }

    private func tapDisc(_ tape: Tape) {
        if selecting || lifted == tape.id {
            actions(tape).tap()
        } else {
            keyClick()
            withAnimation(.spring(duration: 0.3)) { lifted = tape.id }
        }
    }

    @ViewBuilder private var rail: some View {
        if let material {
            LinearGradient(colors: material.side, startPoint: .leading, endPoint: .trailing)
                .frame(width: 10)
        }
    }

    private var material: RackMaterial? {
        switch rack {
        case .deck: nil
        case .shelf: .wood
        case .vault: .steel
        }
    }

    private var backColors: [Color] {
        switch rack {
        case .deck: [Color(hex: 0x1A1A1C), Color(hex: 0x0A0A0B)]
        case .shelf: [Color(hex: 0x2C1C10), Color(hex: 0x1E1309)]
        case .vault: [Color(hex: 0x22262B), Color(hex: 0x15181B)]
        }
    }

    private var border: Color {
        rack == .deck ? Color(hex: 0x2C2C30) : .black.opacity(0.5)
    }
}
