import CoreLocation
import Observation

/// WHERE RECORDED's location service: asks for permission, takes one fix per recording, and
/// looks up the place name nearby. Only "while using the app" access is asked for.
@MainActor
@Observable
final class Locator: NSObject {
    private static let fixTimeout: Duration = .seconds(20)
    /// A fix the phone already has from this recently is good enough.
    private static let freshFix: TimeInterval = 120

    private(set) var status: CLAuthorizationStatus = .notDetermined

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var waitingForAnswer: [CheckedContinuation<Bool, Never>] = []

    override init() {
        super.init()
        status = manager.authorizationStatus
        manager.delegate = self
    }

    var isAllowed: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    /// Turned down, or blocked by Screen Time or a profile: only the Settings app can change it.
    var isRefused: Bool {
        status == .denied || status == .restricted
    }

    /// Asks the first time; after that it says what was answered.
    func requestPermission() async -> Bool {
        guard status == .notDetermined else { return isAllowed }
        return await withCheckedContinuation { continuation in
            waitingForAnswer.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Nil if location isn't allowed, or no fix came in time.
    func fix() async -> LocationFix? {
        guard isAllowed else { return nil }
        if let known = manager.location, -known.timestamp.timeIntervalSinceNow < Self.freshFix {
            return Self.fix(of: known)
        }
        let timeout = Self.fixTimeout
        return await withTaskGroup(of: LocationFix?.self) { group in
            group.addTask { await Self.firstUpdate() }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// "Andrássy út 12, Budapest, HU". Apple's map service looks it up, so it needs the network.
    func placeName(of fix: LocationFix) async -> String? {
        let location = CLLocation(latitude: fix.latitude, longitude: fix.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: .current).first else {
            return nil
        }
        return Self.describe(placemark)
    }

    private nonisolated static func firstUpdate() async -> LocationFix? {
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location {
                    return fix(of: location)
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private nonisolated static func fix(of location: CLLocation) -> LocationFix? {
        let accuracy = location.horizontalAccuracy
        return LocationFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracyM: accuracy >= 0 ? accuracy : nil
        )
    }

    private static func describe(_ placemark: CLPlacemark) -> String? {
        let street = placemark.thoroughfare.map { street in
            placemark.subThoroughfare.map { "\(street) \($0)" } ?? street
        }
        let town = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
        let landmark = placemark.name == town ? nil : placemark.name
        var parts: [String] = []
        for part in [street ?? landmark, town, placemark.isoCountryCode].compactMap({ $0 }) where !parts.contains(part) {
            parts.append(part)
        }
        let name = parts.joined(separator: ", ")
        return name.isEmpty ? nil : String(name.prefix(TapeMeta.placeLimit))
    }

    private func answered(_ newStatus: CLAuthorizationStatus) {
        status = newStatus
        guard newStatus != .notDetermined else { return }
        let waiting = waitingForAnswer
        waitingForAnswer = []
        for continuation in waiting {
            continuation.resume(returning: isAllowed)
        }
    }
}

extension Locator: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        Task { @MainActor in answered(newStatus) }
    }
}
