package com.dic2phone

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaRecorder
import android.util.Log
import java.io.File
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min

/**
 * The tape transport: reads the mic (AudioRecord), listens to it (VU level, finger snaps,
 * the noise gate) and writes AAC-in-MP4 tapes (MediaCodec + MediaMuxer). Runs on its own
 * thread; [stopNow] ends it.
 *
 * Tape time is counted in samples written, so silences skipped by the noise gate simply don't
 * exist on the tape. Each skipped silence leaves [TAIL] + [PRE] (≈1.15 s) of quiet behind,
 * so you can hear there was a cut and the lines don't run into each other.
 *
 * Crash safety: an MP4 is unreadable until it's closed, so every tape also streams its AAC
 * frames into a journal ([Rescue]) that stays playable up to its last byte. A clean finish
 * deletes it; if the app dies mid-tape, the next start rebuilds the tape from it.
 */
class TapeEngine(
    private val ctx: Context,
    gated: Boolean,
    private val snap: Boolean,
    voxSens: Int,
    private val maxTapeMs: Long,
    private val events: Events,
) : Thread("rec-engine") {

    interface Events {
        /** All on the engine thread. */
        fun onTapeStarted(file: File, part: Int)
        fun onFlag(count: Int)
        fun onTapeDone(d: Done)
        fun onFailed(msg: String)
        fun onFinished()
    }

    class Done(
        val file: File, val ok: Boolean, val part: Int, val samples: Long,
        val peak: Int, val rmsDb: Float, val flags: List<Long>,
        val vox: Boolean, val cuts: Int, val skippedMs: Long, val startWall: Long, val endWall: Long,
    ) {
        val durationMs get() = samples * 1000 / SR
    }

    companion object {
        private const val TAG = "TapeEngine"
        const val SR = 44100
        private const val CHUNK = 1024                // ~23 ms
        private const val PRE = SR * 40 / 100         // pre-roll kept before sound returns
        private const val TAIL = SR * 75 / 100        // quiet kept after sound stops
        private const val MAX_PAUSE = SR * 3 / 2      // pauses shorter than this stay untouched
        private const val FADE = SR / 50              // 20 ms fades at cuts
        /** Flags land this far before the moment they were made, so jumping to one gives a lead-in. */
        const val FLAG_LEAD_MS = 1500L
        /** Noise gate floor for each sensitivity (RMS, dBFS). */
        private val VOX_DB = floatArrayOf(-36f, -45f, -53f)
    }

    @Volatile var stopNow = false
    /** Noise-activated: only roll while there's sound. Can change mid-session (latching). */
    @Volatile var gated = gated
    private val flagReq = AtomicInteger()
    fun flag() { flagReq.incrementAndGet() }

    private val voxDb = VOX_DB[voxSens.coerceIn(0, 2)]
    private var writer: Writer? = null
    private var part = 0
    private var flags = mutableListOf<Long>()
    private var cuts = 0
    private var skipped = 0L
    private var failed = false
    private var btRouted = false

    // noise gate
    private var rolling = !gated
    private val pending = ArrayDeque<ShortArray>()
    private var pendingN = 0
    private val ring = ArrayDeque<ShortArray>()
    private var ringN = 0
    private var loudBits = 0
    private var floorDb = -60f

    private val snapper = SnapDetector()

    @SuppressLint("MissingPermission")
    override fun run() {
        var ar: AudioRecord? = null
        try {
            val minBuf = AudioRecord.getMinBufferSize(SR, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            ar = AudioRecord(
                MediaRecorder.AudioSource.MIC, SR, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
                max(minBuf, SR * 2)   // 1 s: room for a tape change without dropping sound
            )
            if (ar.state != AudioRecord.STATE_INITIALIZED) { fail(L.s(R.string.err_mic_unavail)); return }
            Mics.find(ctx, Prefs.mic.value)?.let { d ->
                btRouted = Mics.routeBt(ctx, d)
                if (!ar.setPreferredDevice(d)) Log.w(TAG, "preferred mic refused: ${d.productName}")
                else Log.i(TAG, "recording from ${d.productName} (type ${d.type})")
            }
            ar.startRecording()
            if (ar.recordingState != AudioRecord.RECORDSTATE_RECORDING) { fail(L.s(R.string.err_mic_busy)); return }
            if (!gated) ensureWriter()
            var tick = 0
            var levelPeak = 0
            val buf = ShortArray(CHUNK)
            while (!stopNow && !failed) {
                val n = ar.read(buf, 0, CHUNK)
                if (n < 0) { fail(L.s(R.string.err_mic_stopped, n)); break }
                if (n == 0) continue
                if (stopNow) break            // this chunk may already hold the STOP click
                val c = buf.copyOf(n)
                var pk = 0; var sq = 0.0
                for (s in c) { val a = abs(s.toInt()); if (a > pk) pk = a; sq += a.toDouble() * a }
                val rmsDb = (10 * log10((sq / n).coerceAtLeast(1.0) / (32768.0 * 32768.0))).toFloat()
                if (pk > levelPeak) levelPeak = pk

                if (snap && snapper.feed(c)) addFlag()
                while (flagReq.get() > 0) { flagReq.decrementAndGet(); addFlag() }

                gate(c, rmsDb)

                if (++tick % 4 == 0 && !stopNow) {
                    val db = 20 * log10(levelPeak.coerceAtLeast(1) / 32767f)
                    levelPeak = 0
                    val w = writer
                    Recorder.update {
                        it.copy(
                            level = ((db + 48f) / 48f).coerceIn(0f, 1f),
                            rolling = rolling || !gated,
                            tapeMs = ((w?.samples ?: 0L) + pendingN) * 1000 / SR,
                            vox = gated,
                        )
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "engine", e)
            fail(L.s(R.string.err_rec_failed, e.message ?: e.javaClass.simpleName))
        } finally {
            runCatching { ar?.stop() }
            ar?.release()
            if (btRouted) Mics.releaseBt(ctx)
            // Keep a natural tail of any pause we were holding back, then close the tape.
            if (rolling && pendingN > 0 && writer != null) writeTail()
            finishTape()
            events.onFinished()
        }
    }

    private fun fail(msg: String) {
        failed = true
        events.onFailed(msg)
    }

    // ---- flags --------------------------------------------------------------------------------

    private fun tapePosMs() = ((writer?.samples ?: 0L) + pendingN) * 1000 / SR

    private fun addFlag() {
        val at = (tapePosMs() - FLAG_LEAD_MS).coerceAtLeast(0)
        if (flags.lastOrNull()?.let { at - it < 1000 } == true) return   // one flag per moment
        flags += at
        noteJournal()
        Log.i(TAG, "flag at ${at}ms")
        events.onFlag(flags.size)
    }

    // ---- noise gate ---------------------------------------------------------------------------

    private fun gate(c: ShortArray, rmsDb: Float) {
        // Slow floor tracker: follows quiet quickly, loud slowly, so steady noise (fans) doesn't trip it.
        floorDb += (rmsDb - floorDb) * (if (rmsDb < floorDb) 0.2f else 0.002f)
        val loud = rmsDb > max(voxDb, floorDb + 10f)
        loudBits = ((loudBits shl 1) or (if (loud) 1 else 0)) and 0xF

        if (!gated) {
            if (!rolling) { rolling = true; flushRing(fade = true) }
            flushPending(); write(c); return
        }
        if (rolling) {
            if (loud) { flushPending(); write(c) }
            else {
                pending.addLast(c); pendingN += c.size
                if (pendingN > MAX_PAUSE) cut()
            }
        } else {
            ring.addLast(c); ringN += c.size
            while (ring.size > 1 && ringN - ring.first().size >= PRE) { val d = ring.removeFirst(); ringN -= d.size; skipped += d.size }
            if (Integer.bitCount(loudBits) >= 2) {
                if ((writer?.samples ?: 0L) > 0) cuts++
                rolling = true
                flushRing(fade = (writer?.samples ?: 0L) > 0)
            }
        }
    }

    /** A long silence: keep its first [TAIL] (faded out), remember its last [PRE], drop the rest. */
    private fun cut() {
        writeTail()
        rolling = false
        loudBits = 0
    }

    private fun writeTail() {
        val all = ShortArray(pendingN)
        var o = 0
        pending.forEach { it.copyInto(all, o); o += it.size }
        pending.clear(); pendingN = 0
        val keep = min(TAIL, all.size)
        val head = all.copyOf(keep)
        fade(head, out = true)
        write(head)
        val restStart = max(keep, all.size - PRE)
        skipped += restStart - keep
        if (restStart < all.size) { val r = all.copyOfRange(restStart, all.size); ring.addLast(r); ringN += r.size }
    }

    private fun flushPending() {
        while (pending.isNotEmpty()) write(pending.removeFirst())
        pendingN = 0
    }

    private fun flushRing(fade: Boolean) {
        var first = true
        while (ring.isNotEmpty()) {
            val r = ring.removeFirst()
            if (first && fade) fade(r, out = false)
            first = false
            write(r)
        }
        ringN = 0
    }

    private fun fade(a: ShortArray, out: Boolean) {
        val n = min(FADE, a.size)
        for (i in 0 until n) {
            val g = i.toFloat() / n
            val j = if (out) a.size - 1 - i else i
            a[j] = (a[j] * g).toInt().toShort()
        }
    }

    // ---- tapes --------------------------------------------------------------------------------

    private fun ensureWriter(): Writer {
        writer?.let { return it }
        val f = TapeStore.newTapeFile(ctx)
        part++
        val w = Writer(f, part)
        writer = w
        noteJournal()
        events.onTapeStarted(f, part)
        return w
    }

    private fun write(a: ShortArray) {
        if (a.isEmpty() || failed) return
        val w = try { ensureWriter() } catch (e: Exception) {
            Log.e(TAG, "new tape", e); fail(L.s(R.string.err_rec_failed, e.message ?: e.javaClass.simpleName)); return
        }
        try { w.feed(a) } catch (e: Exception) {
            Log.e(TAG, "encode", e); fail(L.s(R.string.err_rec_failed, e.message ?: e.javaClass.simpleName)); return
        }
        if (w.samples * 1000 / SR >= maxTapeMs) {
            Log.i(TAG, "tape full at ${w.samples * 1000 / SR} ms, rolling onto a new one")
            finishTape()
        }
    }

    /** What a rescue needs besides the sound: when the tape started, its mode and flags. */
    private fun noteJournal() {
        val w = writer ?: return
        runCatching { Rescue.note(w.file, w.startWall, gated || cuts > 0, flags) }
            .onFailure { Log.w(TAG, "journal note", it) }
    }

    private fun finishTape() {
        val w = writer ?: return
        writer = null
        val ok = w.finish()
        val rms = if (w.samples > 0) (10 * log10((w.sumSq / w.samples).coerceAtLeast(1.0) / (32768.0 * 32768.0))).toFloat() else -96f
        events.onTapeDone(
            Done(
                w.file, ok, w.part, w.samples, w.peak, rms, flags.toList(),
                gated || cuts > 0, cuts, skipped * 1000 / SR, w.startWall, System.currentTimeMillis()
            )
        )
        flags = mutableListOf(); cuts = 0; skipped = 0
    }

    /** One tape: AAC-LC encoder into an MP4 muxer. */
    private class Writer(val file: File, val part: Int) {
        val startWall = System.currentTimeMillis()
        var samples = 0L; var peak = 0; var sumSq = 0.0
        private val codec: MediaCodec
        private val muxer: MediaMuxer
        private var track = -1
        private var started = false
        private val info = MediaCodec.BufferInfo()
        /** The crash journal: the same AAC frames as ADTS, readable however it ends. */
        private val journal = runCatching { Rescue.open(file) }.onFailure { Log.w(TAG, "journal", it) }.getOrNull()
        private var frame = ByteArray(2048)
        private var syncedAt = 0L

        init {
            val fmt = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, SR, 1).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, 96_000)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, CHUNK * 2 * 4)
            }
            codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            try {
                codec.configure(fmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                codec.start()
                muxer = MediaMuxer(file.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            } catch (e: Exception) { codec.release(); throw e }
        }

        fun feed(a: ShortArray) {
            var o = 0
            var tries = 0
            while (o < a.size) {
                val idx = codec.dequeueInputBuffer(20_000)
                if (idx < 0) { drain(false); if (++tries > 50) error("encoder stalled"); continue }
                val buf = codec.getInputBuffer(idx)!!
                buf.clear()
                val k = min(a.size - o, buf.remaining() / 2)
                buf.order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().put(a, o, k)
                for (i in o until o + k) {
                    val s = a[i].toInt(); val m = abs(s)
                    if (m > peak) peak = m
                    sumSq += s.toDouble() * s
                }
                codec.queueInputBuffer(idx, 0, k * 2, samples * 1_000_000L / SR, 0)
                samples += k; o += k
                drain(false)
            }
        }

        private fun drain(eos: Boolean) {
            var idle = 0
            while (true) {
                val idx = codec.dequeueOutputBuffer(info, if (eos) 10_000 else 0)
                when {
                    idx == MediaCodec.INFO_TRY_AGAIN_LATER -> { if (!eos || ++idle > 100) return }
                    idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        track = muxer.addTrack(codec.outputFormat)
                        muxer.start(); started = true
                    }
                    idx >= 0 -> {
                        val out = codec.getOutputBuffer(idx)!!
                        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                        if (info.size > 0 && started) {
                            out.position(info.offset); out.limit(info.offset + info.size)
                            muxer.writeSampleData(track, out, info)
                            journal(out)
                        }
                        codec.releaseOutputBuffer(idx, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                    }
                }
            }
        }

        /** Appends one encoded frame to the journal; makes it stick on disk every few seconds. */
        private fun journal(out: java.nio.ByteBuffer) {
            val j = journal ?: return
            try {
                val n = info.size
                if (frame.size < n + 7) frame = ByteArray(n + 7 + 512)
                Rescue.adtsHeader(frame, n)
                out.position(info.offset)
                out.get(frame, 7, n)
                j.write(frame, 0, n + 7)
                if (samples - syncedAt >= SR * 5L) { syncedAt = samples; j.fd.sync() }
            } catch (e: Exception) {
                Log.w(TAG, "journal write", e)
            }
        }

        /** @return true if a playable tape was written. */
        fun finish(): Boolean {
            var ok = false
            try {
                val idx = codec.dequeueInputBuffer(100_000)
                if (idx >= 0) codec.queueInputBuffer(idx, 0, 0, samples * 1_000_000L / SR, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                drain(true)
                if (started && samples > 0) { muxer.stop(); ok = true }
            } catch (e: Exception) {
                Log.e(TAG, "finish ${file.name}", e)
            } finally {
                runCatching { codec.stop() }; codec.release()
                runCatching { muxer.release() }
                runCatching { journal?.close() }
            }
            // A good tape (or one too short to keep) no longer needs its journal; a tape that
            // wouldn't close keeps it, and is rebuilt from it on the next start.
            if (ok || samples < SR) Rescue.drop(file)
            return ok
        }
    }
}

/**
 * Finger-snap (or clap) detector. A snap is a crack: high-frequency energy jumps ≥ 25 dB out
 * of quiet within ~6 ms, is down 15 dB again ~35 ms later and back near the background by
 * ~70 ms, with little low-frequency body, and it stands alone: a quarter second of quiet
 * before it and ~150 ms after. Speech fails on the body test (vowels) and on standing alone
 * (a "t" / "k" / "ch" sits inside words), knocks and thumps on the high-frequency test, music
 * and noise on the sudden-onset test.
 */
class SnapDetector {
    private companion object {
        const val BLK = 256                 // 5.8 ms at 44.1 kHz
        const val HP_A = 0.75f              // one-pole high-pass, ≈2.3 kHz
        const val REFRACTORY = 260          // ≈1.5 s
        const val QUIET_BEFORE = 43         // ≈250 ms of quiet before the crack
        const val SETTLED = 12              // ≈70 ms: crack gone
        const val QUIET_AFTER = 26          // ≈150 ms: nobody went on talking
    }
    private var hpY = 0f; private var hpX = 0f
    private var bgHp = -70f; private var bgAll = -70f
    private var prevHp = -90f
    private var cand = -1                   // blocks since onset, -1 = idle
    private var peak = -90f
    private var cool = 0
    private var quiet = 0                   // blocks in a row near the background
    private val blk = FloatArray(BLK)
    private var fill = 0

    /** @return true when a snap was confirmed somewhere in [c]. */
    fun feed(c: ShortArray): Boolean {
        var hit = false
        for (s in c) {
            blk[fill++] = s.toFloat()
            if (fill == BLK) { if (block()) hit = true; fill = 0 }
        }
        return hit
    }

    private fun block(): Boolean {
        var eAll = 0.0; var eHp = 0.0
        for (x in blk) {
            hpY = HP_A * (hpY + x - hpX); hpX = x
            eAll += x.toDouble() * x; eHp += hpY.toDouble() * hpY
        }
        val full = 32768.0 * 32768.0 * BLK
        val dbAll = (10 * log10(eAll / full + 1e-12)).toFloat()
        val dbHp = (10 * log10(eHp / full + 1e-12)).toFloat()
        var confirmed = false
        if (cool > 0) cool--
        if (cand < 0) {
            val onset = cool == 0 && quiet >= QUIET_BEFORE && dbHp > bgHp + 25f && dbHp > -38f &&
                prevHp < bgHp + 10f && eHp > 0.45 * eAll
            if (onset) { cand = 0; peak = dbHp }
            else {
                bgHp += (dbHp - bgHp) * (if (dbHp < bgHp) 0.1f else 0.01f)
                bgAll += (dbAll - bgAll) * (if (dbAll < bgAll) 0.1f else 0.01f)
            }
        } else {
            cand++
            if (cand <= 1) peak = max(peak, dbHp)
            when {
                cand == 6 -> if (dbHp > peak - 15f) cand = -1
                cand == SETTLED -> if (!(dbHp < bgHp + 12f && dbAll < bgAll + 15f)) cand = -1
                // After the crack it must stay quiet a little; speech carries on into a vowel.
                cand in SETTLED + 1..QUIET_AFTER -> when {
                    dbAll > bgAll + 12f -> cand = -1
                    cand == QUIET_AFTER -> { confirmed = true; cool = REFRACTORY; cand = -1 }
                }
            }
        }
        quiet = if (dbAll < bgAll + 8f && dbHp < bgHp + 10f) quiet + 1 else 0
        prevHp = dbHp
        return confirmed
    }
}
