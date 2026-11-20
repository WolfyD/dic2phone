import Foundation

/// One cycle of a waveform, looked up rather than computed: cheap enough to run several for
/// every sample of an hour-long tape.
struct WaveTable: Sendable {
    private static let size = 4096

    static let sine = WaveTable { sin($0) }
    /// A sine squashed towards a square: the buzzy whine of a small DC motor.
    static let buzz = WaveTable { tanh(3 * sin($0)) }

    private let values: [Float]

    private init(_ wave: (Double) -> Double) {
        values = (0 ..< Self.size).map { Float(wave(2 * Double.pi * Double($0) / Double(Self.size))) }
    }

    /// - Parameter phase: how far through the cycle, 0..<1.
    func value(at phase: Double) -> Float {
        values[Int(phase * Double(Self.size)) & (Self.size - 1)]
    }
}
