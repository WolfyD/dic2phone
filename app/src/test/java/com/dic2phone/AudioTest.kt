package com.dic2phone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlin.random.Random

class AudioTest {
    private val sr = 44_100

    private fun noise(ms: Int, amp: Int, r: Random) = ShortArray(sr * ms / 1000) { (r.nextInt(-amp, amp + 1)).toShort() }

    /** A sharp crack: alternating-sign samples (all high frequency), dying away in ~4 ms. */
    private fun crack(): ShortArray = ShortArray(sr * 4 / 1000) { i ->
        val env = 1 - i / (sr * 4 / 1000f)
        ((if (i % 2 == 0) 1 else -1) * 20_000 * env).toInt().toShort()
    }

    private fun tone(ms: Int, hz: Double, amp: Int) =
        ShortArray(sr * ms / 1000) { (amp * sin(2 * PI * hz * it / sr)).toInt().toShort() }

    @Test fun snapAfterQuietIsDetected() {
        val r = Random(1)
        val d = SnapDetector()
        assertFalse(d.feed(noise(1000, 20, r)))
        d.feed(crack())
        assertTrue(d.feed(noise(400, 20, r)))
    }

    @Test fun quietAndSpeechLikeSoundAreNotSnaps() {
        val r = Random(2)
        val d = SnapDetector()
        assertFalse(d.feed(noise(1000, 20, r)))
        assertFalse(d.feed(tone(400, 220.0, 15_000)))   // a loud low vowel-ish tone
        assertFalse(d.feed(noise(400, 20, r)))
    }

    @Test fun crackFollowedByTalkingIsNotASnap() {
        val r = Random(3)
        val d = SnapDetector()
        d.feed(noise(1000, 20, r))
        d.feed(crack())
        d.feed(noise(80, 20, r))
        assertFalse(d.feed(tone(300, 200.0, 12_000)))
    }

    @Test fun lowpassPassesDcAndCutsTheTop() {
        val lp = Biquad.lowpass(sr, 1000.0, 0.707)
        var y = 0f
        repeat(5000) { y = lp.f(1f) }
        assertEquals(1f, y, 1e-3f)
        var peak = 0f
        val lp2 = Biquad.lowpass(sr, 1000.0, 0.707)
        repeat(5000) { i -> val v = lp2.f(if (i % 2 == 0) 1f else -1f); if (i > 4000) peak = maxOf(peak, abs(v)) }
        assertTrue("nyquist leaks $peak", peak < 1e-3f)
    }

    @Test fun highpassBlocksDc() {
        val hp = Biquad.highpass(sr, 160.0, 0.7)
        var y = 1f
        repeat(20_000) { y = hp.f(1f) }
        assertEquals(0f, y, 1e-3f)
    }

    @Test fun silenceGapsJump() {
        val g = Silence.Gaps(listOf(longArrayOf(1_000, 3_000), longArrayOf(10_000, 12_000)))
        assertNull(g.jump(500))
        assertEquals(3_000L, g.jump(1_000))
        assertEquals(3_000L, g.jump(2_900))
        assertNull(g.jump(2_960))   // too close to the end to bother
        assertEquals(12_000L, g.jump(11_000))
        assertEquals(4_000L, g.totalMs)
    }

    @Test fun adtsHeaderEncodesFrameLength() {
        val b = ByteArray(7)
        Rescue.adtsHeader(b, 300)
        assertEquals(0xFF, b[0].toInt() and 0xFF)
        assertEquals(0xF1, b[1].toInt() and 0xFF)
        val len = ((b[3].toInt() and 3) shl 11) or ((b[4].toInt() and 0xFF) shl 3) or ((b[5].toInt() and 0xFF) ushr 5)
        assertEquals(307, len)
        assertEquals(4, (b[2].toInt() ushr 2) and 0xF)   // 44.1 kHz
    }

    @Test fun durationFormat() {
        assertEquals("0:00", TapeNames.duration(0))
        assertEquals("0:01", TapeNames.duration(500))
        assertEquals("1:05", TapeNames.duration(65_000))
        assertEquals("1:00:00", TapeNames.duration(3_600_000))
    }

    @Test fun tapeFxMask() {
        assertEquals(15, TapeFx().mask)
        assertFalse(TapeFx(false, false, false, false).any)
        assertEquals(4, TapeFx(hiss = false, muffle = false, saturate = false).mask)
    }
}
