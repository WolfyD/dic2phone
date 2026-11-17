package com.dic2phone

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaMuxer
import android.net.Uri
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer

/**
 * Crash journals. While a tape records, its AAC frames also go into deck/.rec/<tape>.aac as raw
 * ADTS, which (unlike the MP4 being written) is playable up to its last byte, plus a small note
 * (start time, mode, flags). A clean finish deletes both. If the app is killed, crashes or the
 * battery dies mid-tape, [recover] (run at the next app start) rebuilds the tape from them.
 */
object Rescue {
    private const val TAG = "Rescue"
    private const val MIN_MS = 700L

    private fun dir(tape: File) = File(tape.parentFile, ".rec")
    private fun aac(tape: File) = File(dir(tape), tape.name + ".aac")
    private fun note(tape: File) = File(dir(tape), tape.name + ".txt")

    fun open(tape: File): FileOutputStream {
        dir(tape).mkdirs()
        return FileOutputStream(aac(tape))
    }

    /** Rewritten whenever it changes (start, each flag): small, and replaced atomically. */
    fun note(tape: File, startWall: Long, vox: Boolean, flags: List<Long>) {
        val n = note(tape)
        val tmp = File(n.path + ".new")
        tmp.writeText("$startWall\n$vox\n${flags.joinToString(",")}\n")
        n.replaceWith(tmp)
    }

    fun drop(tape: File) {
        aac(tape).delete()
        note(tape).delete()
    }

    /** 7-byte ADTS header for one AAC-LC frame of [len] bytes, 44.1 kHz mono, no CRC. */
    fun adtsHeader(b: ByteArray, len: Int) {
        val full = len + 7
        val profile = 2        // AAC LC
        val freq = 4           // 44100
        val chan = 1
        b[0] = 0xFF.toByte()
        b[1] = 0xF1.toByte()
        b[2] = (((profile - 1) shl 6) or (freq shl 2) or (chan shr 2)).toByte()
        b[3] = (((chan and 3) shl 6) or (full shr 11)).toByte()
        b[4] = ((full and 0x7FF) shr 3).toByte()
        b[5] = (((full and 7) shl 5) or 0x1F).toByte()
        b[6] = 0xFC.toByte()
    }

    /**
     * The journals left by a previous run. Taken at app start, before anything can record, so a
     * tape that starts meanwhile is never mistaken for a cut-off one.
     */
    fun leftovers(ctx: Context): List<File> =
        File(TapeStore.deckDir(ctx), ".rec").listFiles { f -> f.isFile && f.name.endsWith(".aac") }.orEmpty().toList()

    /** Rebuilds the tapes that were cut off (from [leftovers]). Slow-ish: off the main thread. */
    fun recover(ctx: Context, journals: List<File>) {
        if (journals.isEmpty()) return
        val d = File(TapeStore.deckDir(ctx), ".rec")
        var saved: String? = null
        for (j in journals) {
            val tape = File(TapeStore.deckDir(ctx), j.name.removeSuffix(".aac"))
            try {
                val ms = synchronized(TapeStore.io) { rebuild(j, tape) }
                if (ms < MIN_MS) {
                    Log.i(TAG, "${tape.name}: nothing worth keeping ($ms ms)")
                    tape.delete()
                } else {
                    saveMeta(ctx, tape, ms, note(tape).takeIf { it.exists() }?.readLines().orEmpty(), j.lastModified())
                    Log.i(TAG, "rescued ${tape.name} ($ms ms)")
                    saved = tape.name
                }
                drop(tape)
            } catch (e: Exception) {
                // Leave the journal for another try; it's still the only copy.
                Log.e(TAG, "rescue ${tape.name}", e)
            }
        }
        d.listFiles { f -> f.name.endsWith(".new") }?.forEach { it.delete() }
        if (saved != null) {
            TapeStore.bump()
            Notifs.showNewTapes(ctx, TapeStore.newCount(ctx), saved)
        }
    }

    /** ADTS journal → MP4 tape. @return the tape's length in ms. */
    private fun rebuild(journal: File, tape: File): Long {
        val tmp = File(tape.path + ".tmp")
        val ex = MediaExtractor()
        var muxer: MediaMuxer? = null
        var lastUs = -1L
        var frames = 0
        try {
            ex.setDataSource(journal.path)
            if (ex.trackCount < 1) return 0
            ex.selectTrack(0)
            val m = MediaMuxer(tmp.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = m
            val track = m.addTrack(ex.getTrackFormat(0))
            m.start()
            val buf = ByteBuffer.allocate(64 * 1024)
            val info = MediaCodec.BufferInfo()
            while (true) {
                // The last frame may be cut short by the crash: stop at whatever won't read.
                val n = runCatching { ex.readSampleData(buf, 0) }.getOrDefault(-1)
                if (n <= 0) break
                info.set(0, n, ex.sampleTime, MediaCodec.BUFFER_FLAG_KEY_FRAME)
                m.writeSampleData(track, buf, info)
                lastUs = ex.sampleTime; frames++
                if (!ex.advance()) break
            }
            if (frames == 0) return 0
            m.stop()
        } finally {
            runCatching { muxer?.release() }
            ex.release()
        }
        if (!tape.replaceWith(tmp)) error("couldn't put the tape in place")
        return (lastUs + 1024L * 1_000_000L / TapeEngine.SR) / 1000
    }

    private fun saveMeta(ctx: Context, tape: File, ms: Long, note: List<String>, endWall: Long) {
        val start = note.getOrNull(0)?.toLongOrNull() ?: (endWall - ms)
        val flags = note.getOrNull(2).orEmpty().split(',').mapNotNull { it.trim().toLongOrNull() }.filter { it < ms }
        val m = TapeMeta(
            startedAt = start, endedAt = endWall, durationMs = ms, sizeBytes = tape.length(),
            format = TapeMeta.FORMAT, device = TapeMeta.DEVICE,
            source = "recovered", vox = note.getOrNull(1) == "true", flags = flags,
        )
        MetaStore.save(ctx, Tape(tape.name, Uri.fromFile(tape), tape, ms, tape.length(), isNew = true), m)
    }
}
