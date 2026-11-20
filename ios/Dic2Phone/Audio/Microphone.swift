/// A mic to record with, as Setup › REC › MICROPHONE lists it. Remembered by `key`, a kind and
/// a name, because the system's own IDs change every time something is plugged in.
struct Microphone: Equatable, Identifiable, Sendable {
    /// Bluetooth mics only send sound over a call-quality link, so there's one choice for them:
    /// whichever headset is connected.
    static let bluetoothKey = "bt:"

    let key: String
    let label: String

    var id: String { key }
}
