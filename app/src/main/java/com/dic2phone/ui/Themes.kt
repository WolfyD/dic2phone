package com.dic2phone.ui

import androidx.compose.ui.graphics.Color

/** One complete look for the deck. Used by the app UI, widgets and the live wallpaper. */
data class Palette(
    val id: String,
    val name: String,
    val bgTop: Color, val bgBottom: Color,
    val grid: Color? = null,              // synthwave perspective grid
    val panel: Color, val text: Color, val dim: Color,
    val key1: Color, val key2: Color, val keyText: Color,
    val brand1: Color, val brand2: Color,
    val label: Color, val ink: Color, val stripes: List<Color>,
    val shell1: Color, val shell2: Color, val window: Color, val pack: Color, val hub: Color,
    val vu1: Color, val vu2: Color, val vuInk: Color, val vuRed: Color,
    val led: Color, val ledOff: Color,
    val accent: Color, val danger: Color,
    val counterBg: Color, val counterDigit: Color,
    val rec1: Color, val rec2: Color,
)

object Themes {
    val Walnut = Palette(
        id = "walnut", name = "HI-FI WALNUT",
        bgTop = Color(0xFF221B15), bgBottom = Color(0xFF120E0B),
        panel = Color(0xFF2A241F), text = Color(0xFFE6DCC6), dim = Color(0xFF9A8F7E),
        key1 = Color(0xFFEDEAE3), key2 = Color(0xFF9C978E), keyText = Color(0xFF1E1E1E),
        brand1 = Color.White, brand2 = Color(0xFF9C978E),
        label = Color(0xFFF1E7CC), ink = Color(0xFF243048),
        stripes = listOf(Color(0xFFF2B33D), Color(0xFFE8642A), Color(0xFFD7322E)),
        shell1 = Color(0xFF34343A), shell2 = Color(0xFF18181B), window = Color(0xFF120E10),
        pack = Color(0xFF4A2E1F), hub = Color(0xFFEDEDED),
        vu1 = Color(0xFFFBE7A8), vu2 = Color(0xFFE6B852), vuInk = Color(0xFF2A2018), vuRed = Color(0xFFD7322E),
        led = Color(0xFFFF3B2F), ledOff = Color(0xFF4A1C18),
        accent = Color(0xFFF2B33D), danger = Color(0xFFD7322E),
        counterBg = Color(0xFF0C0C0C), counterDigit = Color(0xFFF4F1E8),
        rec1 = Color(0xFFD9473F), rec2 = Color(0xFF7E1813),
    )

    val MiamiNeon = Palette(
        id = "miami", name = "MIAMI NEON",
        bgTop = Color(0xFF2A1248), bgBottom = Color(0xFF0D0618),
        panel = Color(0xFF2E1650), text = Color(0xFFF7E8FF), dim = Color(0xFFB79CD9),
        key1 = Color(0xFFFFFFFF), key2 = Color(0xFFC7B6E8), keyText = Color(0xFF2B0F4C),
        brand1 = Color(0xFFFF6EC7), brand2 = Color(0xFF00E5D4),
        label = Color(0xFFFFF0FA), ink = Color(0xFF2B0F4C),
        stripes = listOf(Color(0xFF00E5D4), Color(0xFF8A5CFF), Color(0xFFFF2E97)),
        shell1 = Color(0xFF3B2457), shell2 = Color(0xFF170B28), window = Color(0xFF0A0512),
        pack = Color(0xFF3A1E3A), hub = Color(0xFFF0F0FF),
        vu1 = Color(0xFF2A1446), vu2 = Color(0xFF14082A), vuInk = Color(0xFF00E5D4), vuRed = Color(0xFFFF2E97),
        led = Color(0xFFFF2E97), ledOff = Color(0xFF4A1036),
        accent = Color(0xFF00E5D4), danger = Color(0xFFFF2E97),
        counterBg = Color(0xFF0A0512), counterDigit = Color(0xFFFF6EC7),
        rec1 = Color(0xFFFF4FA8), rec2 = Color(0xFF9C0F5C),
    )

    val ChromeWalkman = Palette(
        id = "chrome", name = "CHROME WALKMAN",
        bgTop = Color(0xFFDDE0E5), bgBottom = Color(0xFF8C929B),
        panel = Color(0xFFB8BDC4), text = Color(0xFF1C2633), dim = Color(0xFF4A5566),
        key1 = Color(0xFF3A3E45), key2 = Color(0xFF121417), keyText = Color(0xFFE8ECF1),
        brand1 = Color(0xFF1C2633), brand2 = Color(0xFF6C7888),
        label = Color(0xFF1C1C1E), ink = Color(0xFFD8DCE2),
        stripes = listOf(Color(0xFF2D6CDF), Color(0xFFBFC5CC), Color(0xFFF28C28)),
        shell1 = Color(0xFF3A3D43), shell2 = Color(0xFF16171A), window = Color(0xFF0B0B0D),
        pack = Color(0xFF2B1F18), hub = Color(0xFFDADDE2),
        vu1 = Color(0xFFEEF1F5), vu2 = Color(0xFFC3CAD3), vuInk = Color(0xFF1C2633), vuRed = Color(0xFFF28C28),
        led = Color(0xFFFF5A1F), ledOff = Color(0xFF5A3424),
        accent = Color(0xFF2D6CDF), danger = Color(0xFFE5482A),
        counterBg = Color(0xFF121417), counterDigit = Color(0xFFE8ECF1),
        rec1 = Color(0xFFF0643C), rec2 = Color(0xFFA8321A),
    )

    val Synthwave = Palette(
        id = "synthwave", name = "SYNTHWAVE SUNSET",
        bgTop = Color(0xFF0B1033), bgBottom = Color(0xFF5A1450), grid = Color(0xFFFF2975),
        panel = Color(0xFF20184A), text = Color(0xFFFFE3F1), dim = Color(0xFFC59AD0),
        key1 = Color(0xFF2E2468), key2 = Color(0xFF120C33), keyText = Color(0xFF2DE2E6),
        brand1 = Color(0xFFFFD319), brand2 = Color(0xFFFF2975),
        label = Color(0xFF1B1035), ink = Color(0xFFFFD3F0),
        stripes = listOf(Color(0xFFFFD319), Color(0xFFFF901F), Color(0xFFFF2975)),
        shell1 = Color(0xFF2A1F55), shell2 = Color(0xFF0E0822), window = Color(0xFF070414),
        pack = Color(0xFF3A1240), hub = Color(0xFF2DE2E6),
        vu1 = Color(0xFF1B1035), vu2 = Color(0xFF0B0620), vuInk = Color(0xFF2DE2E6), vuRed = Color(0xFFFF2975),
        led = Color(0xFF2DE2E6), ledOff = Color(0xFF10394A),
        accent = Color(0xFF2DE2E6), danger = Color(0xFFFF2975),
        counterBg = Color(0xFF070414), counterDigit = Color(0xFFFFD319),
        rec1 = Color(0xFFFF2975), rec2 = Color(0xFF8A0F45),
    )

    val BeigeBoombox = Palette(
        id = "beige", name = "BEIGE BOOMBOX",
        bgTop = Color(0xFFE6DDC9), bgBottom = Color(0xFFBFB397),
        panel = Color(0xFFD3C8AE), text = Color(0xFF2F2A22), dim = Color(0xFF6E6450),
        key1 = Color(0xFF4A4A4A), key2 = Color(0xFF232323), keyText = Color(0xFFF2EEE4),
        brand1 = Color(0xFF2F2A22), brand2 = Color(0xFF8A7F68),
        label = Color(0xFFFAF8F2), ink = Color(0xFF2F2A22),
        stripes = listOf(
            Color(0xFFE03A3E), Color(0xFFF5821F), Color(0xFFFDB827), Color(0xFF61BB46), Color(0xFF009DDC)
        ),
        shell1 = Color(0xFF3C3C3C), shell2 = Color(0xFF1E1E1E), window = Color(0xFF101010),
        pack = Color(0xFF4A2E1F), hub = Color(0xFFEDEDED),
        vu1 = Color(0xFFB2CBA3), vu2 = Color(0xFF86A477), vuInk = Color(0xFF1E2A16), vuRed = Color(0xFFB3261E),
        led = Color(0xFFE53935), ledOff = Color(0xFF6A3A38),
        accent = Color(0xFFE0701A), danger = Color(0xFFB3261E),
        counterBg = Color(0xFF9DB38A), counterDigit = Color(0xFF1E2A16),
        rec1 = Color(0xFFE04A3F), rec2 = Color(0xFF8E1C17),
    )

    /** Plain dark: graphite greys and black, with leather-brown and brass highlights. */
    val Graphite = Palette(
        id = "graphite", name = "GRAPHITE",
        bgTop = Color(0xFF1E1F21), bgBottom = Color(0xFF09090A),
        panel = Color(0xFF242528), text = Color(0xFFE0DBD3), dim = Color(0xFF8D8880),
        key1 = Color(0xFF4B4C50), key2 = Color(0xFF1C1D20), keyText = Color(0xFFD8BE9C),
        brand1 = Color(0xFFD2AE84), brand2 = Color(0xFF6E4B30),
        label = Color(0xFF2E2F33), ink = Color(0xFFD8C1A2),
        stripes = listOf(Color(0xFFB4875C), Color(0xFF7E5636), Color(0xFF4E3220)),
        shell1 = Color(0xFF303135), shell2 = Color(0xFF111113), window = Color(0xFF060606),
        pack = Color(0xFF3B2B1F), hub = Color(0xFFB9B5AE),
        vu1 = Color(0xFF2B2622), vu2 = Color(0xFF141210), vuInk = Color(0xFFDDB98A), vuRed = Color(0xFFC4603F),
        led = Color(0xFFE88A45), ledOff = Color(0xFF3A2618),
        accent = Color(0xFFC08C5C), danger = Color(0xFFC4603F),
        counterBg = Color(0xFF101010), counterDigit = Color(0xFFD8BE9C),
        rec1 = Color(0xFFA9452F), rec2 = Color(0xFF561C12),
    )

    val all = listOf(Walnut, MiamiNeon, ChromeWalkman, Synthwave, BeigeBoombox, Graphite)
    fun byId(id: String?) = all.firstOrNull { it.id == id } ?: Walnut
}
