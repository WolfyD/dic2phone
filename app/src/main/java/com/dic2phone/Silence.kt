package com.dic2phone

import android.content.Context
import android.util.Log
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min

/**
 * Finds the long silences on a tape, for SKIP SILENCE playback. The tape is decoded once (in
 * the background, the first time it's played with skipping on) and the quiet stretches kept
 * in memory. Each gap keeps a little quiet at both ends so speech doesn't run together.
 */
object Silence {
    private const val SR = 16_000
    private const val WIN = SR / 20               // 50 ms windows
    private const val MIN_GAP_MS = 1200L          // shorter pauses are left alone
    private const val KEEP_MS = 300L              // quiet kept either side of a skip

    /** Skippable stretches, as (from, to) in ms. */
    class Gaps(val list: List<LongArray>) {
        /** Where to jump if [ms] is inside a gap, else null. */
        fun jump(ms: Long): Long? = list.firstOrNull { ms >= it[0] && ms < it[1] - 50 }?.get(1)
        val totalMs get() = list.sumOf { it[1] - it[0] }
    }

    private val cache = ConcurrentHashMap<String, Gaps>()
    private fun key(t: Tape) = "${t.id}:${t.sizeBytes}"

    fun cached(t: Tape): Gaps? = cache[key(t)]

    /** Decodes [t] and finds its gaps. Slow (seconds for a long tape): call off the main thread. */
    fun find(ctx: Context, t: Tape, stop: () -> Boolean): Gaps? {
        cache[key(t)]?.let { return it }
        val db = ArrayList<Float>(((t.durationMs / 50) + 16).toInt().coerceAtMost(200_000))
        var acc = 0.0; var n = 0
        try {
            Transcriber.decode16k(ctx, t, if (t.vault != null) Vault.currentKey() else null) { chunk ->
                for (v in chunk) {
                    acc += v * v; n++
                    if (n == WIN) { db += (10 * log10(acc / n + 1e-10)).toFloat(); acc = 0.0; n = 0 }
                }
                !stop()
            }
        } catch (e: Exception) {
            Log.w("Silence", "decode ${t.id}", e); return null
        }
        if (stop() || db.isEmpty()) return null
        // Quiet = well below this tape's own background level, whatever the room was like.
        val sorted = db.sorted()
        val floor = sorted[sorted.size / 10]
        val thr = min(max(floor + 9f, -62f), -32f)
        val gaps = mutableListOf<LongArray>()
        var start = -1
        fun close(end: Int) {
            val a = start * 50L + KEEP_MS; val b = end * 50L - KEEP_MS
            if (end * 50L - start * 50L >= MIN_GAP_MS && b - a >= 400) gaps += longArrayOf(a, b)
        }
        // A single loud blip (a click, a cough of noise) doesn't end a silence.
        for (i in db.indices) {
            val quiet = db[i] < thr || (db[i] < thr + 6 && i > 0 && i < db.size - 1 && db[i - 1] < thr && db[i + 1] < thr)
            if (quiet) { if (start < 0) start = i }
            else if (start >= 0) { close(i); start = -1 }
        }
        if (start >= 0) close(db.size)
        return Gaps(gaps).also {
            cache[key(t)] = it
            Log.i("Silence", "${t.id}: ${gaps.size} gaps, ${it.totalMs} ms (floor ${"%.1f".format(floor)} dB, thr ${"%.1f".format(thr)})")
        }
    }
}
