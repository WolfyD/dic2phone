import Foundation

/// How tapes are named on screen: "19 NOV 2026", "14:03:22", "1:02:03".
enum TapeNames {
    static func date(_ date: Date, locale: Locale = .current) -> String {
        formatted(date, as: "dd MMM yyyy", locale: locale)
    }

    static func time(_ date: Date) -> String {
        formatted(date, as: "HH:mm:ss", locale: Locale(identifier: "en_US_POSIX"))
    }

    static func clock(_ date: Date, locale: Locale = .current) -> String {
        formatted(date, as: "dd MMM yyyy  HH:mm:ss", locale: locale)
    }

    /// Rounded to the second: "4:05", or "1:02:03" past an hour.
    static func duration(ms: Int64) -> String {
        let totalSeconds = (ms + 500) / 1000
        let hours = totalSeconds / 3600
        let minutes = totalSeconds / 60 % 60
        let seconds = totalSeconds % 60
        return hours > 0
            ? String(format: "%lld:%02lld:%02lld", hours, minutes, seconds)
            : String(format: "%lld:%02lld", minutes, seconds)
    }

    /// The label for a tape with no title: its recording date and time.
    static func pretty(_ id: TapeID) -> String {
        guard let date = id.recordedAt else { return id.baseName }
        return "\(Self.date(date)) \(time(date))"
    }

    /// The recording date and time apart, for lists that set them on separate lines.
    static func dateAndTime(_ id: TapeID) -> (date: String, time: String) {
        guard let recordedAt = id.recordedAt else { return (id.baseName, "") }
        return (date(recordedAt), time(recordedAt))
    }

    static func label(_ tape: Tape) -> String {
        tape.title.isEmpty ? pretty(tape.id) : tape.title
    }

    private static func formatted(_ date: Date, as pattern: String, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = pattern
        return formatter.string(from: date).uppercased(with: locale)
    }
}
