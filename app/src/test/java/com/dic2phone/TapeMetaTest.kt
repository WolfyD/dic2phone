package com.dic2phone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class TapeMetaTest {
    private val full = TapeMeta(
        title = "Standup", notes = "line 1\nline 2", tags = listOf("work", "ideas"),
        startedAt = 1_700_000_000_000, endedAt = 1_700_000_060_000, durationMs = 60_000, sizeBytes = 720_000,
        format = TapeMeta.FORMAT, peakDb = -3.5f, avgDb = -28.25f, source = "rec-key", device = "Pixel",
        latched = true, vox = true, cuts = 3, skippedMs = 4_200, part = 2,
        lat = 47.4979, lon = 19.0402, accuracyM = 12.5f, place = "Budapest, HU",
        flags = listOf(1_000, 30_000), flagNotes = mapOf(1_000L to "first", 30_000L to "second"),
    )

    @Test fun jsonRoundTrip() {
        assertEquals(full, TapeMeta.parse(full.toJson().toString()))
    }

    @Test fun emptyMetaWritesNothingButVersion() {
        val o = TapeMeta().toJson()
        assertEquals(listOf("v"), o.keys().asSequence().toList())
        assertEquals(TapeMeta(), TapeMeta.fromJson(o))
    }

    @Test fun notesOfRemovedFlagsAreDropped() {
        val m = full.copy(flags = listOf(30_000), flagNotes = full.flagNotes + (5L to "  "))
        val back = TapeMeta.parse(m.toJson().toString())!!
        assertEquals(mapOf(30_000L to "second"), back.flagNotes)
    }

    @Test fun flagsComeBackSorted() {
        val back = TapeMeta.parse("""{"v":1,"flags":[900,100,500]}""")!!
        assertEquals(listOf(100L, 500L, 900L), back.flags)
    }

    @Test fun badJsonIsNull() {
        assertNull(TapeMeta.parse("{not json"))
        assertNull(TapeMeta.parse(null))
    }

    @Test fun placeNeedsBothCoordinates() {
        assertFalse(TapeMeta(lat = 1.0).hasPlace)
    }
}
