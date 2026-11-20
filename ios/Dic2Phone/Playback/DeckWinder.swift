import Observation

/// REW and FF. A tap winds ten seconds. Held, the deck keeps winding until the key is let go:
/// by ten-second skips, or with TAPE WIND on like a real deck, the counter racing to the motor's
/// whirr. A tape that was playing plays on from wherever the wind stops.
@MainActor
@Observable
final class DeckWinder {
    private static let skipMs: Int64 = 10_000
    private static let skipRepeatDelay: Duration = .milliseconds(450)
    private static let skipRepeatInterval: Duration = .milliseconds(160)
    /// Held longer than this, TAPE WIND winds; let go sooner, it was a tap.
    private static let windHoldDelay: Duration = .milliseconds(300)
    private static let motorTick: Duration = .milliseconds(30)

    private enum Hold {
        case skipping
        case aboutToWind(forward: Bool)
        case winding(playsOn: Bool)
    }

    /// For the reels, which turn as the tape winds.
    private(set) var isWinding = false

    @ObservationIgnored private let player: Player
    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private let feedback: Feedback
    @ObservationIgnored private var hold: Hold?
    @ObservationIgnored private var holding: Task<Void, Never>?

    init(player: Player, settings: Settings, feedback: Feedback) {
        self.player = player
        self.settings = settings
        self.feedback = feedback
    }

    func press(forward: Bool) {
        holding?.cancel()
        if settings.tapeWind {
            hold = .aboutToWind(forward: forward)
            holding = Task { [weak self] in
                try? await Task.sleep(for: Self.windHoldDelay)
                guard !Task.isCancelled else { return }
                await self?.wind(forward: forward)
            }
        } else {
            hold = .skipping
            skip(forward: forward)
            holding = Task { [weak self] in
                try? await Task.sleep(for: Self.skipRepeatDelay)
                while !Task.isCancelled {
                    self?.skip(forward: forward)
                    try? await Task.sleep(for: Self.skipRepeatInterval)
                }
            }
        }
    }

    func release() {
        holding?.cancel()
        holding = nil
        switch hold {
        case .aboutToWind(let forward):
            skip(forward: forward)
        case .winding(let playsOn):
            feedback.key()
            if playsOn { player.playOn() }
        case .skipping, nil:
            break
        }
        hold = nil
        isWinding = false
    }

    private func skip(forward: Bool) {
        player.skip(byMs: forward ? Self.skipMs : -Self.skipMs)
    }

    private func wind(forward: Bool) async {
        guard let tape = player.loaded else { return }
        hold = .winding(playsOn: player.deckPlaying)
        isWinding = true
        if player.deckPlaying { player.stop() }
        feedback.windStart()
        defer { feedback.windStop() }
        let clock = ContinuousClock()
        let started = clock.now
        var last = started
        // Let go mid-tick, the sleep ends early: no last step, the tape may be playing again.
        while (try? await Task.sleep(for: Self.motorTick)) != nil, player.loadedID == tape.id {
            let now = clock.now
            let spinUp = WindMotor.spinUp(after: now - started)
            feedback.windSpeed(spinUp)
            let before = player.deckPositionMs
            let woundMs = WindMotor.woundMs(in: now - last, spinUp: spinUp)
            player.seek(toMs: before + (forward ? woundMs : -woundMs))
            last = now
            if player.deckPositionMs == before {
                feedback.windEnd()
                isWinding = false
                return
            }
        }
    }
}
