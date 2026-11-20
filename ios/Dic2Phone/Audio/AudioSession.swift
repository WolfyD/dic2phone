import AVFoundation

/// The app's one audio session: recording, playback and deck sounds all share it.
@MainActor
final class AudioSession {
    private let session = AVAudioSession.sharedInstance()

    /// Mixes with other apps, like the Android app: deck clicks and tapes never stop the user's
    /// music. A2DP rather than Bluetooth HFP, so a headset doesn't drag the mic down to call
    /// quality. iOS mutes haptics while recording unless told otherwise, and FLAG and the REC
    /// lock rely on them.
    func configure() throws {
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers]
        )
        try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
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
