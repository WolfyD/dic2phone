import SwiftUI

/// The six deck looks, matching the Android app colour for colour.
enum Themes {
    static let walnut = Palette(
        id: "walnut", name: "HI-FI WALNUT",
        bgTop: Color(hex: 0x221B15), bgBottom: Color(hex: 0x120E0B),
        panel: Color(hex: 0x2A241F), text: Color(hex: 0xE6DCC6), dim: Color(hex: 0x9A8F7E),
        key1: Color(hex: 0xEDEAE3), key2: Color(hex: 0x9C978E), keyText: Color(hex: 0x1E1E1E),
        brand1: Color(hex: 0xFFFFFF), brand2: Color(hex: 0x9C978E),
        label: Color(hex: 0xF1E7CC), ink: Color(hex: 0x243048),
        stripes: [Color(hex: 0xF2B33D), Color(hex: 0xE8642A), Color(hex: 0xD7322E)],
        shell1: Color(hex: 0x34343A), shell2: Color(hex: 0x18181B), window: Color(hex: 0x120E10),
        pack: Color(hex: 0x4A2E1F), hub: Color(hex: 0xEDEDED),
        vu1: Color(hex: 0xFBE7A8), vu2: Color(hex: 0xE6B852), vuInk: Color(hex: 0x2A2018), vuRed: Color(hex: 0xD7322E),
        led: Color(hex: 0xFF3B2F), ledOff: Color(hex: 0x4A1C18),
        accent: Color(hex: 0xF2B33D), danger: Color(hex: 0xD7322E),
        counterBg: Color(hex: 0x0C0C0C), counterDigit: Color(hex: 0xF4F1E8),
        rec1: Color(hex: 0xD9473F), rec2: Color(hex: 0x7E1813)
    )

    static let miamiNeon = Palette(
        id: "miami", name: "MIAMI NEON",
        bgTop: Color(hex: 0x2A1248), bgBottom: Color(hex: 0x0D0618),
        panel: Color(hex: 0x2E1650), text: Color(hex: 0xF7E8FF), dim: Color(hex: 0xB79CD9),
        key1: Color(hex: 0xFFFFFF), key2: Color(hex: 0xC7B6E8), keyText: Color(hex: 0x2B0F4C),
        brand1: Color(hex: 0xFF6EC7), brand2: Color(hex: 0x00E5D4),
        label: Color(hex: 0xFFF0FA), ink: Color(hex: 0x2B0F4C),
        stripes: [Color(hex: 0x00E5D4), Color(hex: 0x8A5CFF), Color(hex: 0xFF2E97)],
        shell1: Color(hex: 0x3B2457), shell2: Color(hex: 0x170B28), window: Color(hex: 0x0A0512),
        pack: Color(hex: 0x3A1E3A), hub: Color(hex: 0xF0F0FF),
        vu1: Color(hex: 0x2A1446), vu2: Color(hex: 0x14082A), vuInk: Color(hex: 0x00E5D4), vuRed: Color(hex: 0xFF2E97),
        led: Color(hex: 0xFF2E97), ledOff: Color(hex: 0x4A1036),
        accent: Color(hex: 0x00E5D4), danger: Color(hex: 0xFF2E97),
        counterBg: Color(hex: 0x0A0512), counterDigit: Color(hex: 0xFF6EC7),
        rec1: Color(hex: 0xFF4FA8), rec2: Color(hex: 0x9C0F5C)
    )

    static let chromeWalkman = Palette(
        id: "chrome", name: "CHROME WALKMAN",
        bgTop: Color(hex: 0xDDE0E5), bgBottom: Color(hex: 0x8C929B),
        panel: Color(hex: 0xB8BDC4), text: Color(hex: 0x1C2633), dim: Color(hex: 0x4A5566),
        key1: Color(hex: 0x3A3E45), key2: Color(hex: 0x121417), keyText: Color(hex: 0xE8ECF1),
        brand1: Color(hex: 0x1C2633), brand2: Color(hex: 0x6C7888),
        label: Color(hex: 0x1C1C1E), ink: Color(hex: 0xD8DCE2),
        stripes: [Color(hex: 0x2D6CDF), Color(hex: 0xBFC5CC), Color(hex: 0xF28C28)],
        shell1: Color(hex: 0x3A3D43), shell2: Color(hex: 0x16171A), window: Color(hex: 0x0B0B0D),
        pack: Color(hex: 0x2B1F18), hub: Color(hex: 0xDADDE2),
        vu1: Color(hex: 0xEEF1F5), vu2: Color(hex: 0xC3CAD3), vuInk: Color(hex: 0x1C2633), vuRed: Color(hex: 0xF28C28),
        led: Color(hex: 0xFF5A1F), ledOff: Color(hex: 0x5A3424),
        accent: Color(hex: 0x2D6CDF), danger: Color(hex: 0xE5482A),
        counterBg: Color(hex: 0x121417), counterDigit: Color(hex: 0xE8ECF1),
        rec1: Color(hex: 0xF0643C), rec2: Color(hex: 0xA8321A)
    )

    static let synthwave = Palette(
        id: "synthwave", name: "SYNTHWAVE SUNSET",
        bgTop: Color(hex: 0x0B1033), bgBottom: Color(hex: 0x5A1450), grid: Color(hex: 0xFF2975),
        panel: Color(hex: 0x20184A), text: Color(hex: 0xFFE3F1), dim: Color(hex: 0xC59AD0),
        key1: Color(hex: 0x2E2468), key2: Color(hex: 0x120C33), keyText: Color(hex: 0x2DE2E6),
        brand1: Color(hex: 0xFFD319), brand2: Color(hex: 0xFF2975),
        label: Color(hex: 0x1B1035), ink: Color(hex: 0xFFD3F0),
        stripes: [Color(hex: 0xFFD319), Color(hex: 0xFF901F), Color(hex: 0xFF2975)],
        shell1: Color(hex: 0x2A1F55), shell2: Color(hex: 0x0E0822), window: Color(hex: 0x070414),
        pack: Color(hex: 0x3A1240), hub: Color(hex: 0x2DE2E6),
        vu1: Color(hex: 0x1B1035), vu2: Color(hex: 0x0B0620), vuInk: Color(hex: 0x2DE2E6), vuRed: Color(hex: 0xFF2975),
        led: Color(hex: 0x2DE2E6), ledOff: Color(hex: 0x10394A),
        accent: Color(hex: 0x2DE2E6), danger: Color(hex: 0xFF2975),
        counterBg: Color(hex: 0x070414), counterDigit: Color(hex: 0xFFD319),
        rec1: Color(hex: 0xFF2975), rec2: Color(hex: 0x8A0F45)
    )

    static let beigeBoombox = Palette(
        id: "beige", name: "BEIGE BOOMBOX",
        bgTop: Color(hex: 0xE6DDC9), bgBottom: Color(hex: 0xBFB397),
        panel: Color(hex: 0xD3C8AE), text: Color(hex: 0x2F2A22), dim: Color(hex: 0x6E6450),
        key1: Color(hex: 0x4A4A4A), key2: Color(hex: 0x232323), keyText: Color(hex: 0xF2EEE4),
        brand1: Color(hex: 0x2F2A22), brand2: Color(hex: 0x8A7F68),
        label: Color(hex: 0xFAF8F2), ink: Color(hex: 0x2F2A22),
        stripes: [
            Color(hex: 0xE03A3E), Color(hex: 0xF5821F), Color(hex: 0xFDB827), Color(hex: 0x61BB46), Color(hex: 0x009DDC),
        ],
        shell1: Color(hex: 0x3C3C3C), shell2: Color(hex: 0x1E1E1E), window: Color(hex: 0x101010),
        pack: Color(hex: 0x4A2E1F), hub: Color(hex: 0xEDEDED),
        vu1: Color(hex: 0xB2CBA3), vu2: Color(hex: 0x86A477), vuInk: Color(hex: 0x1E2A16), vuRed: Color(hex: 0xB3261E),
        led: Color(hex: 0xE53935), ledOff: Color(hex: 0x6A3A38),
        accent: Color(hex: 0xE0701A), danger: Color(hex: 0xB3261E),
        counterBg: Color(hex: 0x9DB38A), counterDigit: Color(hex: 0x1E2A16),
        rec1: Color(hex: 0xE04A3F), rec2: Color(hex: 0x8E1C17)
    )

    static let graphite = Palette(
        id: "graphite", name: "GRAPHITE",
        bgTop: Color(hex: 0x1E1F21), bgBottom: Color(hex: 0x09090A),
        panel: Color(hex: 0x242528), text: Color(hex: 0xE0DBD3), dim: Color(hex: 0x8D8880),
        key1: Color(hex: 0x4B4C50), key2: Color(hex: 0x1C1D20), keyText: Color(hex: 0xD8BE9C),
        brand1: Color(hex: 0xD2AE84), brand2: Color(hex: 0x6E4B30),
        label: Color(hex: 0x2E2F33), ink: Color(hex: 0xD8C1A2),
        stripes: [Color(hex: 0xB4875C), Color(hex: 0x7E5636), Color(hex: 0x4E3220)],
        shell1: Color(hex: 0x303135), shell2: Color(hex: 0x111113), window: Color(hex: 0x060606),
        pack: Color(hex: 0x3B2B1F), hub: Color(hex: 0xB9B5AE),
        vu1: Color(hex: 0x2B2622), vu2: Color(hex: 0x141210), vuInk: Color(hex: 0xDDB98A), vuRed: Color(hex: 0xC4603F),
        led: Color(hex: 0xE88A45), ledOff: Color(hex: 0x3A2618),
        accent: Color(hex: 0xC08C5C), danger: Color(hex: 0xC4603F),
        counterBg: Color(hex: 0x101010), counterDigit: Color(hex: 0xD8BE9C),
        rec1: Color(hex: 0xA9452F), rec2: Color(hex: 0x561C12)
    )

    static let all = [walnut, miamiNeon, chromeWalkman, synthwave, beigeBoombox, graphite]

    static func palette(id: String) -> Palette {
        all.first { $0.id == id } ?? walnut
    }
}
