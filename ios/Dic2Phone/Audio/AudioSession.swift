import AVFoundation

/// The app's one audio session: recording, playback and deck sounds all share it.
@MainActor
final class AudioSession {
    private let session = AVAudioSession.sharedInstance()
    /// Bluetooth's call-quality link, on only while recording from a Bluetooth mic.
    private var handsFree = false

    /// Mixes with other apps, like the Android app: deck clicks and tapes never stop the user's
    /// music. A2DP rather than Bluetooth HFP, so a headset doesn't drag the mic down to call
    /// quality. iOS mutes haptics while recording unless told otherwise, and FLAG and the REC
    /// lock rely on them.
    func configure() throws {
        try setCategory(handsFree: false)
        try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
    }

    /// What can be recorded from now. A Bluetooth headset's mic isn't listed by iOS until the
    /// call-quality link is on, so a connected headset stands for it.
    var microphones: [Microphone] {
        var found = MicPorts.microphones(in: session.availableInputs ?? [])
        if bluetoothConnected, !found.contains(MicPorts.bluetooth) {
            found.append(MicPorts.bluetooth)
        }
        return found
    }

    /// Before recording: asks for the chosen mic. One that isn't connected leaves it to iOS.
    func useMicrophone(_ key: String) {
        let wantsBluetooth = key == Microphone.bluetoothKey
        if wantsBluetooth != handsFree {
            try? setCategory(handsFree: wantsBluetooth)
        }
        guard let match = MicPorts.find(key, in: session.availableInputs ?? []) else {
            try? session.setPreferredInput(nil)
            return
        }
        try? session.setPreferredInput(match.port)
        if let source = match.source {
            try? match.port.setPreferredDataSource(source)
        }
    }

    /// After recording: a Bluetooth headset goes back to full-quality sound.
    func finishRecording() {
        if handsFree {
            try? setCategory(handsFree: false)
        }
    }

    func activate() throws {
        try session.setActive(true)
    }

    var micPermission: AVAudioApplication.recordPermission {
        AVAudioApplication.shared.recordPermission
    }

    func requestMicPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    var headphonesConnected: Bool {
        let headphonePorts: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothLE, .usbAudio]
        return session.currentRoute.outputs.contains { headphonePorts.contains($0.portType) }
    }

    private var bluetoothConnected: Bool {
        let bluetoothPorts: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothLE, .bluetoothHFP]
        return session.currentRoute.outputs.contains { bluetoothPorts.contains($0.portType) }
    }

    /// With both Bluetooth options on, iOS prefers the call-quality link for a headset that
    /// offers both, so it's added only when a Bluetooth mic is wanted.
    private func setCategory(handsFree: Bool) throws {
        var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers]
        if handsFree {
            options.insert(.allowBluetooth)
        }
        try session.setCategory(.playAndRecord, mode: .default, options: options)
        self.handsFree = handsFree
    }

    /// The system's output volume, 0...1.
    var outputVolume: Float {
        session.outputVolume
    }

    /// A phone call or alarm took the audio away.
    nonisolated static func isInterruptionStart(_ notification: Notification) -> Bool {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return false }
        return type == .began
    }
}
