import CoreHaptics

/// Plays haptic patterns on the Taptic Engine. Phones without one simply get none.
@MainActor
final class Haptics {
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?

    func play(_ pattern: HapticPattern) {
        guard supported else { return }
        do {
            let engine = try preparedEngine()
            // Starting again is cheap, and revives an engine the system stopped or reset.
            try engine.start()
            try engine.makePlayer(with: pattern.hapticPattern()).start(atTime: CHHapticTimeImmediate)
        } catch {
            engine = nil
        }
    }

    private func preparedEngine() throws -> CHHapticEngine {
        if let engine { return engine }
        let created = try CHHapticEngine()
        created.playsHapticsOnly = true
        created.isAutoShutdownEnabled = true
        engine = created
        return created
    }
}
