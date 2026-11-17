package com.dic2phone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CaptionsTest {
    private val cues = listOf(
        Cue(0, 1_500, "Hello there"),
        Cue(2_000, 4_250, "two\nlines"),
        Cue(3_723_004, 3_725_000, "over an hour in"),
    )

    @Test fun srtRoundTrip() {
        assertEquals(cues, Captions.parse(Captions.toSrt(cues)))
    }

    @Test fun srtTimestampsAreFormatted() {
        val srt = Captions.toSrt(cues)
        assertTrue(srt.contains("00:00:02,000 --> 00:00:04,250"))
        assertTrue(srt.contains("01:02:03,004 --> 01:02:05,000"))
    }

    @Test fun parsesCrlfDotsAndShortMillis() {
        val srt = "1\r\n00:00:01.5 --> 00:00:02.25\r\n  padded  \r\n\r\n"
        assertEquals(listOf(Cue(1_500, 2_250, "padded")), Captions.parse(srt))
    }

    @Test fun parseIgnoresJunk() {
        assertEquals(emptyList<Cue>(), Captions.parse("not a caption file\n\n"))
    }

    @Test fun atFindsCueAndLingersThenClears() {
        assertEquals("Hello there", Captions.at(cues, 700)?.text)
        assertEquals("Hello there", Captions.at(cues, 1_900)?.text)   // inside the linger
        assertEquals("two\nlines", Captions.at(cues, 2_000)?.text)
        assertNull(Captions.at(cues, 10_000))                          // in a long gap
        assertNull(Captions.at(emptyList(), 0))
    }

    @Test fun foldStripsAccentsAndKeepsLength() {
        val s = "Árvíztűrő TÜKÖRFÚRÓGÉP"
        val f = Captions.fold(s)
        assertEquals("arvizturo tukorfurogep", f)
        assertEquals(s.length, f.length)
    }

    @Test fun foldedMatchIndicesMapBack() {
        val text = "Café crème"
        val i = Captions.fold(text).indexOf(Captions.fold("CREME"))
        assertEquals("crème", text.substring(i, i + 5))
    }

    @Test fun blankSearchFindsNothing() {
        assertTrue(Captions.search(emptyList(), "   ").isEmpty())
    }
}
