import CoreHaptics

/// A vibration written like an Android waveform: step lengths in milliseconds, each with an
/// amplitude 0...255. Kept in that form so the patterns match the Android app's exactly.
struct HapticPattern: Sendable {
    let stepsMs: [Int]
    let amplitudes: [Int]

    /// The contact and the latch clack of the REC sound.
    static let recStart = HapticPattern(stepsMs: [12, 10, 58, 40], amplitudes: [0, 90, 0, 255])
    /// STOP clack, the keys releasing, the mechanism's thud.
    static let recStop = HapticPattern(stepsMs: [55, 35, 95, 15, 80, 30], amplitudes: [0, 255, 0, 140, 0, 200])
    static let flag = HapticPattern(stepsMs: [0, 18], amplitudes: [0, 200])
    static let latch = HapticPattern(stepsMs: [0, 30, 70, 30], amplitudes: [0, 255, 0, 255])
    static let doorOpen = HapticPattern(stepsMs: [70, 12, 78, 14, 76, 30], amplitudes: [0, 90, 0, 140, 0, 255])
    static let doorClose = HapticPattern(stepsMs: [10, 18, 332, 30], amplitudes: [0, 120, 0, 255])
    static let detent = HapticPattern(stepsMs: [0, 10], amplitudes: [0, 120])

    func hapticPattern() throws -> CHHapticPattern {
        var events: [CHHapticEvent] = []
        var startMs = 0
        for (lengthMs, amplitude) in zip(stepsMs, amplitudes) {
            if amplitude > 0 {
                events.append(CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(amplitude) / 255),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6),
                    ],
                    relativeTime: Double(startMs) / 1000,
                    duration: Double(lengthMs) / 1000
                ))
            }
            startMs += lengthMs
        }
        return try CHHapticPattern(events: events, parameters: [])
    }
}
