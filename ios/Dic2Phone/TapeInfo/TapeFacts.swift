import Foundation

/// What the recorder wrote down about a tape, as TAPE INFO lists it.
enum TapeFacts {
    /// Android's silence floor, shown when a tape has a peak level but no average.
    private static let silentDb = -96.0

    static func of(_ tape: Tape, meta: TapeMeta) -> [TapeFact] {
        let facts: [TapeFact?] = [
            fact("RECORDED", recorded(tape, meta: meta)),
            meta.endedAtMs > 0 ? fact("ENDED", clock(ms: meta.endedAtMs)) : nil,
            fact("LENGTH", length(tape, meta: meta)),
            fact("SIZE", size(tape, meta: meta)),
            fact("FORMAT", meta.format.isEmpty ? TapeFormat.label : meta.format),
            meta.peakDb.map { fact("LEVEL", level(peakDb: $0, averageDb: meta.averageDb)) },
            meta.source.isEmpty ? nil : fact("STARTED BY", startedBy(meta.source)),
            mode(meta).map { fact("MODE", $0) },
            meta.flags.isEmpty ? fact("FLAGS", String(localized: "none")) : nil,
            meta.device.isEmpty ? nil : fact("DEVICE", meta.device),
            fact("FILE", tape.id.baseName + "  " + rackName(tape.rack)),
        ]
        return facts.compactMap { $0 }
    }

    /// The `source` names are the Android app's too, so imported tapes read the same.
    static func startedBy(_ source: String) -> String {
        switch source {
        case let s where s.hasPrefix("rec-key"): String(localized: "REC key on the deck")
        case let s where s.hasPrefix("vol-down"): String(localized: "Volume-down trigger")
        case let s where s.hasPrefix("headset"): String(localized: "Headset button")
        case let s where s.hasPrefix("quick:android.intent.action.ASSIST"): String(localized: "Squeeze / assistant gesture")
        case let s where s.hasPrefix("quick:"): String(localized: "Quick REC (icon, tile or side key)")
        case let s where s.hasPrefix("widget"): String(localized: "Home-screen widget")
        case let s where s.hasPrefix("tile"): String(localized: "Quick settings tile")
        case let s where s.hasPrefix("split"): String(localized: "Continued from the previous hour")
        case let s where s.hasPrefix("recovered"): String(localized: "Rescued after the recording was cut off")
        default: source
        }
    }

    private static func fact(_ name: String.LocalizationValue, _ value: String) -> TapeFact {
        TapeFact(name: String(localized: name), value: value)
    }

    private static func recorded(_ tape: Tape, meta: TapeMeta) -> String {
        meta.startedAtMs > 0 ? clock(ms: meta.startedAtMs) : TapeNames.pretty(tape.id)
    }

    private static func length(_ tape: Tape, meta: TapeMeta) -> String {
        let length = TapeNames.duration(ms: meta.durationMs > 0 ? meta.durationMs : tape.durationMs)
        return meta.part > 0 ? length + "  ·  " + String(localized: "TAPE \(meta.part)") : length
    }

    private static func size(_ tape: Tape, meta: TapeMeta) -> String {
        ByteCountFormatter.string(fromByteCount: tape.sizeBytes > 0 ? tape.sizeBytes : meta.sizeBytes, countStyle: .decimal)
    }

    private static func level(peakDb: Double, averageDb: Double?) -> String {
        let peak = decibels(peakDb)
        let average = decibels(averageDb ?? silentDb)
        return String(localized: "peak \(peak) dB · avg \(average) dB")
    }

    private static func mode(_ meta: TapeMeta) -> String? {
        var parts: [String] = []
        if meta.latched {
            parts.append(String(localized: "locked on"))
        } else if !meta.source.isEmpty {
            parts.append(String(localized: "held"))
        }
        if meta.vox {
            let cuts = meta.cuts > 0
                ? ", " + String(localized: "\(meta.cuts) silences cut (\(TapeNames.duration(ms: meta.skippedMs)))")
                : ""
            parts.append(String(localized: "noise-activated") + cuts)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func rackName(_ rack: Rack) -> String {
        switch rack {
        case .deck: String(localized: "(deck)")
        case .shelf: String(localized: "(shelf)")
        case .vault: String(localized: "(vault)")
        }
    }

    private static func clock(ms: Int64) -> String {
        TapeNames.clock(Date(timeIntervalSince1970: TimeInterval(ms) / 1000))
    }

    private static func decibels(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
