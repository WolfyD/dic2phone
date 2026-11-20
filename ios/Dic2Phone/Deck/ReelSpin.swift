import SwiftUI

/// How far the reels have turned. They turn at a steady rate while the tape moves and stay where
/// they stopped, so a pause doesn't snap them back.
struct ReelSpin {
    private static let degreesPerSecond = 220.0

    private var restingDegrees = 0.0
    private var startedAt: Date?

    func angle(at date: Date) -> Angle {
        .degrees(degrees(at: date))
    }

    mutating func update(spinning: Bool, at date: Date = .now) {
        if spinning {
            if startedAt == nil { startedAt = date }
        } else {
            restingDegrees = degrees(at: date)
            startedAt = nil
        }
    }

    private func degrees(at date: Date) -> Double {
        guard let startedAt else { return restingDegrees }
        // A frame stamped just before the start would turn the reels back a hair.
        let turned = max(date.timeIntervalSince(startedAt), 0) * Self.degreesPerSecond
        return (restingDegrees + turned).truncatingRemainder(dividingBy: 360)
    }
}
