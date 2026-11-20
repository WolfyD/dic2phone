import SwiftUI

/// The main screen: the cassette, the counters, the VU meter or the loaded tape's player, and the
/// keys. Upright it's a pocket recorder; sideways it's a tape deck with the keys along the front.
struct DeckScreen: View {
    /// The reels' tape pack fills up over ten minutes of recording.
    private static let fullReelMs: CGFloat = 600_000

    let navigate: (Screen) -> Void

    @Environment(Settings.self) private var settings
    @Environment(TapeLibrary.self) private var library
    @Environment(Recorder.self) private var recorder
    @Environment(Player.self) private var player
    @Environment(FlagKey.self) private var flagKey
    @Environment(CaptionQueue.self) private var captions
    @Environment(\.palette) private var palette
    @Environment(\.keyClick) private var keyClick
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var writingLabel = false
    @State private var titling: Tape?

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.2, paused: !recorder.state.recording)) { timeline in
            let elapsedMs = recorder.state.recording
                ? max(Int64(timeline.date.timeIntervalSince(recorder.state.startedAt) * 1000), 0)
                : 0
            if verticalSizeClass == .compact {
                landscape(elapsedMs: elapsedMs)
            } else {
                portrait(elapsedMs: elapsedMs)
            }
        }
        .labelWritingAlert(
            isPresented: $writingLabel,
            original: settings.tapeLabel,
            placeholder: String(localized: "e.g. NOTES or MIXTAPE '89"),
            limit: Settings.labelLimit,
            hint: String(localized: "Leave empty for a blank label"),
            onWrite: settings.setTapeLabel
        )
        .labelWritingAlert(
            isPresented: Binding { titling != nil } set: { if !$0 { titling = nil } },
            original: titling?.title ?? "",
            placeholder: titling.map { TapeNames.pretty($0.id) } ?? "",
            limit: TapeMeta.titleLimit,
            hint: String(localized: "Up to \(TapeMeta.titleLimit) letters"),
            onWrite: { [titling] title in
                // Captured now: closing the alert clears `titling` before or after WRITE runs.
                guard let titling else { return }
                Task { await library.setTitle(title, of: titling) }
            }
        )
    }

    /// The tape in the deck, unless recording has taken it over.
    private var inDeck: Tape? {
        recorder.state.recording ? nil : player.loaded
    }

    private var keys: DeckKeys {
        DeckKeys(
            recorder: recorder, player: player, flagKey: flagKey,
            palette: palette, keyClick: keyClick, navigate: navigate
        )
    }

    private func portrait(elapsedMs: Int64) -> some View {
        let tape = inDeck
        return ScrollView {
            VStack(spacing: tape == nil ? 14 : 6) {
                BrandPlate()
                counterRow(elapsedMs: elapsedMs)
                // Smaller with a tape in, to make room for its player.
                cassette(elapsedMs: elapsedMs)
                    .containerRelativeFrame(.horizontal) { length, _ in (length - 32) * (tape == nil ? 1 : 0.82) }
                if let tape {
                    status
                    DeckPlayer(tape: tape, transport: keys.transport)
                } else {
                    vuMeter
                        .containerRelativeFrame(.horizontal) { length, _ in (length - 32) * 0.8 }
                    status
                }
                KeyBank(keys: keys.deck, keyHeight: tape == nil ? 112 : 68)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func landscape(elapsedMs: Int64) -> some View {
        let tape = inDeck
        return VStack(spacing: 8) {
            HStack(spacing: 16) {
                cassette(elapsedMs: elapsedMs)
                    .layoutPriority(1)
                VStack(spacing: 6) {
                    BrandPlate()
                    counterRow(elapsedMs: elapsedMs)
                    Group {
                        if let tape {
                            ScrollView { DeckPlayer(tape: tape, transport: nil) }
                        } else {
                            vuMeter.padding(.horizontal)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    status
                }
            }
            landscapeKeys(tape: tape)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// The transport gets its own bank on the front row beside the deck's keys: there's no room
    /// for it beside the cassette.
    private func landscapeKeys(tape: Tape?) -> some View {
        let deckKeys = keys.deck
        let transport = tape == nil ? nil : keys.transport
        return WeightedRow(spacing: 12) {
            if let transport {
                KeyBank(keys: transport, keyHeight: 64)
                    .layoutWeight(Self.totalWeight(of: transport))
            }
            KeyBank(keys: deckKeys, keyHeight: 64)
                .layoutWeight(Self.totalWeight(of: deckKeys))
        }
    }

    private func counterRow(elapsedMs: Int64) -> some View {
        CounterRow(
            newCount: library.newCount,
            recording: recorder.state.recording,
            elapsedMs: elapsedMs,
            onDeck: library.deck.count,
            onReset: library.markAllHeard
        )
    }

    private func cassette(elapsedMs: Int64) -> some View {
        CassetteView(
            label: cassetteLabel,
            spinning: recorder.state.tapeMoving || player.deckPlaying,
            progress: cassetteProgress(elapsedMs: elapsedMs),
            typed: settings.labelTyped
        )
        .onTapGesture {
            keyClick()
            navigate(.load)
        }
        .onLongPressGesture {
            keyClick()
            writeOnLabel()
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Opens the tapes to load one"))
        .accessibilityAction(named: Text("Write on the label"), writeOnLabel)
    }

    private var cassetteLabel: CassetteLabel {
        if let tape = inDeck {
            return .inDeck(tape, positionMs: player.deckPositionMs, playing: player.deckPlaying)
        }
        return .empty(userLabel: settings.tapeLabel, recording: recorder.state.recording, last: library.lastTape)
    }

    private func cassetteProgress(elapsedMs: Int64) -> CGFloat {
        if recorder.state.recording {
            return min(CGFloat(elapsedMs) / Self.fullReelMs, 1)
        }
        guard let tape = inDeck, tape.durationMs > 0 else { return 0 }
        return min(max(CGFloat(player.deckPositionMs) / CGFloat(tape.durationMs), 0), 1)
    }

    private var vuMeter: some View {
        VuMeter(level: recorder.state.recording ? recorder.state.level : 0)
    }

    @ViewBuilder private var status: some View {
        if recorder.state.recording {
            RecStatus(state: recorder.state)
        }
        if let problem = recorder.state.error ?? library.problem ?? captionProblem {
            Text(verbatim: "\(Glyph.warning) \(problem)")
                .font(DeckFont.mono.fixed(12))
                .foregroundStyle(palette.accent)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }

    private var captionProblem: String? {
        captions.lastError.map { String(localized: "TRANSCRIBING FAILED: \($0)") }
    }

    /// With a tape in, its title; with none, the deck's own label.
    private func writeOnLabel() {
        if let tape = inDeck {
            titling = tape
        } else {
            writingLabel = true
        }
    }

    private static func totalWeight(of keys: [BankKey]) -> CGFloat {
        keys.reduce(0) { $0 + $1.weight }
    }
}
