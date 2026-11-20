import AVFoundation
import Observation

/// MICROPHONE's state: the mics connected now and which one recording asks for.
@MainActor
@Observable
final class MicChooser {
    private(set) var microphones: [Microphone] = []

    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private let audioSession: AudioSession

    init(settings: Settings, audioSession: AudioSession) {
        self.settings = settings
        self.audioSession = audioSession
    }

    /// Empty for AUTO.
    var chosen: String {
        settings.microphone
    }

    var chosenIsMissing: Bool {
        !chosen.isEmpty && !microphones.contains { $0.key == chosen }
    }

    func choose(_ key: String) {
        settings.microphone = key
    }

    /// Keeps the list current as things are plugged in and out, for as long as it's shown.
    func watch() async {
        microphones = audioSession.microphones
        let routeChanges = NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification)
        for await _ in routeChanges {
            microphones = audioSession.microphones
        }
    }
}
