import Foundation

/// Where the phone was when a tape was recorded.
struct LocationFix: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    /// How far off the fix may be, in metres; nil if it didn't say.
    let accuracyM: Double?

    /// Nil for coordinates that are nowhere on Earth, as a damaged or crafted file could hold.
    init?(latitude: Double, longitude: Double, accuracyM: Double?) {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyM = accuracyM.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }

    /// "47.50213° N, 19.06401° E", the same on every phone whatever its language.
    var coordinates: String {
        "\(Self.degrees(latitude)) \(latitude >= 0 ? "N" : "S"), \(Self.degrees(longitude)) \(longitude >= 0 ? "E" : "W")"
    }

    /// Apple Maps, with a pin named `label` on the spot.
    func mapsURL(label: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "q", value: label),
        ]
        return components.url
    }

    private static func degrees(_ value: Double) -> String {
        abs(value).formatted(.number.precision(.fractionLength(5)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))) + "°"
    }
}
