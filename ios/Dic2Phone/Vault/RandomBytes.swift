import Foundation

/// Random bytes for keys, nonces and file ids. The system generator is the platform's
/// cryptographically secure one, and using it keeps this free of unsafe pointer APIs.
enum RandomBytes {
    static func make(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}
