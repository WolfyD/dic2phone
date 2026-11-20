/// The languages captions can be made in, as whisper.cpp codes. "auto" lets whisper guess per tape.
enum CaptionLanguage {
    static let automatic = "auto"
    static let codes = [automatic, "en", "hu", "de", "fr", "es", "it", "pl", "ro", "nl", "pt", "cs"]

    static func label(_ code: String) -> String {
        code == automatic ? String(localized: "AUTO") : code.uppercased()
    }
}
