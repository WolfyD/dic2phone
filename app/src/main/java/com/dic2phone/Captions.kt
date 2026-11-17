package com.dic2phone

import android.content.Context
import java.io.File
import java.text.Normalizer

data class Cue(val startMs: Long, val endMs: Long, val text: String)

/**
 * Captions are stored as .srt, keyed by the tape's file name, so they follow a tape from the
 * deck to the shelf for free. Vault tapes keep theirs sealed inside the vault.
 */
object Captions {
    fun dir(ctx: Context) = File(ctx.filesDir, "captions").apply { mkdirs() }
    fun file(ctx: Context, id: String) = File(dir(ctx), id.substringBeforeLast('.') + ".srt")

    fun delete(ctx: Context, id: String) { file(ctx, id).delete() }

    fun loadSrt(ctx: Context, t: Tape): String? =
        if (t.vault != null) Vault.readCaption(ctx, t.vault)
        else file(ctx, t.id).takeIf { it.exists() }?.readText()

    fun load(ctx: Context, t: Tape): List<Cue>? = loadSrt(ctx, t)?.let(::parse)

    // ---- SRT ---------------------------------------------------------------------------------

    fun toSrt(cues: List<Cue>): String = buildString {
        cues.forEachIndexed { i, c ->
            append(i + 1).append('\n')
            append(ts(c.startMs)).append(" --> ").append(ts(c.endMs)).append('\n')
            append(c.text).append("\n\n")
        }
    }

    private fun ts(ms: Long): String =
        "%02d:%02d:%02d,%03d".format(ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)

    private val TIME = Regex("""(\d+):(\d\d):(\d\d)[,.](\d{1,3})\s*-->\s*(\d+):(\d\d):(\d\d)[,.](\d{1,3})""")

    fun parse(srt: String): List<Cue> {
        val out = mutableListOf<Cue>()
        val lines = srt.replace("\r", "").split('\n')
        var i = 0
        while (i < lines.size) {
            val m = TIME.find(lines[i])
            if (m == null) { i++; continue }
            val g = m.groupValues
            fun ms(o: Int) = g[o].toLong() * 3_600_000 + g[o + 1].toLong() * 60_000 + g[o + 2].toLong() * 1000 +
                g[o + 3].padEnd(3, '0').toLong()
            val text = StringBuilder()
            i++
            while (i < lines.size && lines[i].isNotBlank()) {
                if (text.isNotEmpty()) text.append('\n')
                text.append(lines[i].trim()); i++
            }
            out += Cue(ms(1), ms(5), text.toString())
        }
        return out
    }

    // ---- Reading ------------------------------------------------------------------------------

    fun at(cues: List<Cue>, ms: Long): Cue? {
        // Binary search for the last cue starting at or before ms.
        var lo = 0; var hi = cues.size - 1; var best = -1
        while (lo <= hi) {
            val mid = (lo + hi) / 2
            if (cues[mid].startMs <= ms) { best = mid; lo = mid + 1 } else hi = mid - 1
        }
        val c = cues.getOrNull(best) ?: return null
        return if (ms <= c.endMs + 1500) c else null   // linger a moment, then clear in gaps
    }

    /** A readable transcript: paragraphs broken at pauses, each with its start time. */
    fun transcript(t: Tape, cues: List<Cue>): String = buildString {
        append(L.s(R.string.tape_name, TapeNames.pretty(t.id))).append('\n')
        var lastEnd = -10_000L
        cues.forEach { c ->
            if (c.startMs - lastEnd > 2500) {
                if (isNotEmpty()) append("\n\n")
                append('[').append(TapeNames.duration(c.startMs)).append("] ")
            } else append(' ')
            append(c.text.trim())
            lastEnd = c.endMs
        }
        append('\n')
    }

    // ---- Search -------------------------------------------------------------------------------

    /** Lower-case, accents stripped, same length as the input (so match indices map back). */
    fun fold(s: String): String {
        val sb = StringBuilder(s.length)
        for (ch in s) {
            val d = Normalizer.normalize(ch.toString(), Normalizer.Form.NFD)
            sb.append(d[0].lowercaseChar())
        }
        return sb.toString()
    }

    class Hit(val tape: Tape, val cue: Cue, val start: Int, val end: Int)

    fun search(index: List<Pair<Tape, List<Cue>>>, query: String, limit: Int = 300): List<Hit> {
        val q = fold(query.trim())
        if (q.isEmpty()) return emptyList()
        val out = mutableListOf<Hit>()
        for ((t, cues) in index) for (c in cues) {
            val i = fold(c.text).indexOf(q)
            if (i >= 0) {
                out += Hit(t, c, i, i + q.length)
                if (out.size >= limit) return out
            }
        }
        return out
    }
}
