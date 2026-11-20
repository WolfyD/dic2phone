/// TAPE WIND's motor: it starts slow and spins up over three seconds, the tape running past the
/// heads ever faster.
enum WindMotor {
    /// Tape time wound per real time, at a standstill and at full speed.
    private static let slowestRate = 6.0
    private static let fastestRate = 30.0
    private static let spinUpTime: Duration = .seconds(3)

    /// How far the motor has spun up, from 0 to 1, after running for `elapsed`.
    static func spinUp(after elapsed: Duration) -> Double {
        min(max(elapsed / spinUpTime, 0), 1)
    }

    /// The tape wound in `interval`, in milliseconds.
    static func woundMs(in interval: Duration, spinUp: Double) -> Int64 {
        let rate = slowestRate + (fastestRate - slowestRate) * spinUp * spinUp
        return Int64(rate * (interval / .milliseconds(1)))
    }
}
