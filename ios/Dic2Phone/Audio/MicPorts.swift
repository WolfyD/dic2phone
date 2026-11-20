import AVFoundation

/// Turns the audio session's inputs into microphones to choose from, and a chosen one back into
/// the input to ask for.
@MainActor
enum MicPorts {
    /// Names come from the accessory itself, so they're cut to a length that fits a key.
    private static let nameLimit = 24

    private struct Entry {
        let microphone: Microphone
        let port: AVAudioSessionPortDescription
        let source: AVAudioSessionDataSourceDescription?
    }

    static var bluetooth: Microphone {
        Microphone(key: Microphone.bluetoothKey, label: String(localized: "BLUETOOTH"))
    }

    static func microphones(in inputs: [AVAudioSessionPortDescription]) -> [Microphone] {
        var seen: Set<String> = []
        return entries(in: inputs).map(\.microphone).filter { seen.insert($0.key).inserted }
    }

    /// Nil if that mic isn't connected now.
    static func find(
        _ key: String,
        in inputs: [AVAudioSessionPortDescription]
    ) -> (port: AVAudioSessionPortDescription, source: AVAudioSessionDataSourceDescription?)? {
        entries(in: inputs).first { $0.microphone.key == key }.map { ($0.port, $0.source) }
    }

    private static func entries(in inputs: [AVAudioSessionPortDescription]) -> [Entry] {
        inputs.flatMap(entries(of:))
    }

    private static func entries(of port: AVAudioSessionPortDescription) -> [Entry] {
        let name = String(port.portName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(nameLimit)).uppercased()
        switch port.portType {
        case .builtInMic:
            return builtIn(port)
        case .headsetMic:
            return [Entry(microphone: Microphone(key: "wired:", label: String(localized: "HEADSET")), port: port, source: nil)]
        case .usbAudio:
            let label = "USB · " + (name.isEmpty ? String(localized: "MIC") : name)
            return [Entry(microphone: Microphone(key: "usb:" + name, label: label), port: port, source: nil)]
        case .bluetoothHFP:
            return [Entry(microphone: bluetooth, port: port, source: nil)]
        default:
            return []
        }
    }

    /// An iPhone has several mics in one port: bottom, front, back.
    private static func builtIn(_ port: AVAudioSessionPortDescription) -> [Entry] {
        let phone = String(localized: "PHONE")
        guard let sources = port.dataSources, sources.count > 1 else {
            return [Entry(microphone: Microphone(key: "builtin:", label: phone), port: port, source: nil)]
        }
        return sources.map { source in
            let side = source.orientation?.rawValue ?? source.dataSourceName
            let microphone = Microphone(key: "builtin:" + side, label: phone + " · " + source.dataSourceName.uppercased())
            return Entry(microphone: microphone, port: port, source: source)
        }
    }
}
