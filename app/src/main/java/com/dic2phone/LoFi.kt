package com.dic2phone

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import android.util.Log
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.tanh
import kotlin.random.Random

/** Which "old portable recorder" effects to bake into a copy. */
data class TapeFx(
    val hiss: Boolean = true,      // tape hiss + transport motor noise
    val muffle: Boolean = true,    // dull, band-limited tone
    val wow: Boolean = true,       // wow & flutter (pitch wobble)
    val saturate: Boolean = true,  // soft tape compression
) {
    val any get() = hiss || muffle || wow || saturate
    val mask get() = (if (hiss) 1 else 0) or (if (muffle) 2 else 0) or (if (wow) 4 else 0) or (if (saturate) 8 else 0)
}

/**
 * Renders a tape-effect copy of a recording: decode AAC → process PCM → encode AAC (m4a).
 * Originals are never touched; copies live in the cache and are pruned after a couple of days.
 */
object LoFi {
    private const val TAG = "LoFi"

    fun dir(ctx: Context) = File(ctx.cacheDir, "lofi")

    private fun outFile(ctx: Context, t: Tape, fx: TapeFx) =
        File(File(dir(ctx), "fx${fx.mask}"), t.id.substringBeforeLast('.') + SUFFIX)

    /** The copy, if it's already rendered. */
    fun ready(ctx: Context, t: Tape, fx: TapeFx): File? = outFile(ctx, t, fx).takeIf { it.length() > 0 }

    private val bg = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val warming = ConcurrentHashMap<String, Deferred<File?>>()

    /**
     * Renders the copy in the background (once, however many ask), independent of playback:
     * stopping the tape doesn't throw the work away. Rendering runs ~15× real time, so a long
     * tape takes a while; the deck warms its tape up as soon as it's loaded.
     */
    fun warm(ctx: Context, t: Tape, fx: TapeFx): Deferred<File?> {
        val app = ctx.applicationContext
        ready(app, t, fx)?.let { return CompletableDeferred(it) }
        val key = outFile(app, t, fx).path
        synchronized(warming) {
            warming[key]?.takeIf { it.isActive }?.let { return it }
            return bg.async { copy(app, t, fx) }.also { warming[key] = it }
        }
    }

    /** Cached tape-effect copy of [t] (rendered if needed), or null on failure/cancel. */
    fun copy(ctx: Context, t: Tape, fx: TapeFx, cancelled: () -> Boolean = { false }): File? {
        val out = outFile(ctx, t, fx)
        val d = out.parentFile!!.apply { mkdirs() }
        if (out.length() > 0) return out
        val tmp = File(d, out.name + ".part")
        val t0 = System.currentTimeMillis()
        val ok = runCatching { render(ctx, t.uri, tmp, fx, cancelled) }
            .onFailure { Log.e(TAG, "render ${t.id}", it) }
            .getOrDefault(false)
        if (ok && tmp.renameTo(out)) {
            Log.i(TAG, "rendered ${out.name} fx=${fx.mask} in ${System.currentTimeMillis() - t0}ms")
            return out
        }
        tmp.delete()
        return null
    }

    // ---- Keeping copies ------------------------------------------------------------------------
    // Copies are kept: rendering a long tape takes a while, and they live in the cache, which
    // Android empties by itself when storage runs low. Gone with their tape; optionally also
    // when unplayed for [Prefs.fxKeepDays].

    private const val SUFFIX = "_tape.m4a"
    private fun copies(ctx: Context) = dir(ctx).walk().filter { it.isFile && it.name.endsWith(SUFFIX) }

    /** Number of copies and the space they take. */
    fun usage(ctx: Context): Pair<Int, Long> = copies(ctx).fold(0 to 0L) { (n, b), f -> n + 1 to b + f.length() }

    /** Played: resets its "unplayed for" clock. */
    fun touch(f: File) { f.setLastModified(System.currentTimeMillis()) }

    /** Tapes deleted or locked in the vault: their copies go too (a vault tape's would be plaintext). */
    fun forget(ctx: Context, ids: Collection<String>) {
        val names = ids.map { it.substringBeforeLast('.') + SUFFIX }.toSet()
        copies(ctx).filter { it.name in names }.forEach { it.delete() }
    }

    /** Deletes copies whose tape is gone ([live] = ids of deck and shelf tapes), and unplayed ones if set. */
    fun tidy(ctx: Context, live: Set<String>) {
        val keep = live.map { it.substringBeforeLast('.') + SUFFIX }.toSet()
        val days = Prefs.fxKeepDays.value
        val cutoff = if (days > 0) System.currentTimeMillis() - days * 86_400_000L else Long.MIN_VALUE
        var n = 0
        copies(ctx).filter { it.name !in keep || it.lastModified() < cutoff }.forEach { if (it.delete()) n++ }
        // Half-made copies left by a crash.
        val stale = System.currentTimeMillis() - 86_400_000L
        dir(ctx).walk().filter { it.isFile && it.name.endsWith(".part") && it.lastModified() < stale }.forEach { it.delete() }
        if (n > 0) Log.i(TAG, "tidied $n copies")
    }

    /** CLEAR NOW: every copy (renders in progress just fail and play clean). */
    fun clear(ctx: Context) { copies(ctx).forEach { it.delete() } }

    private class Pcm(val sr: Int, val data: FloatArray, val eos: Boolean)
    private class Aborted : RuntimeException()

    /**
     * Each MediaCodec call costs a millisecond or more (IPC + buffer allocation), so the four
     * codec ends run on their own threads and overlap:
     * extractor→decoder | decoder→effects→queue | queue→encoder | encoder→muxer.
     */
    private fun render(ctx: Context, src: Uri, out: File, fx: TapeFx, cancelled: () -> Boolean): Boolean {
        val ex = MediaExtractor()
        var dec: MediaCodec? = null
        val enc = AtomicReference<MediaCodec?>()
        var mux: MediaMuxer? = null
        val muxStarted = AtomicBoolean(false)
        val done = AtomicBoolean(false)
        val abort = AtomicBoolean(false)
        val err = AtomicReference<Throwable?>()
        val threads = CopyOnWriteArrayList<Thread>()
        val q = LinkedBlockingQueue<Pcm>(16)

        fun spawn(name: String, body: () -> Unit) {
            threads += thread(name = "lofi-$name") {
                try { body() } catch (_: Aborted) {
                } catch (t: Throwable) { err.compareAndSet(null, t); abort.set(true) }
            }
        }
        fun check() { if (abort.get()) throw Aborted() }

        try {
            ex.setDataSource(ctx, src, null)
            val ti = (0 until ex.trackCount).firstOrNull {
                ex.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: return false
            ex.selectTrack(ti)
            val inFmt = ex.getTrackFormat(ti)
            val d = MediaCodec.createDecoderByType(inFmt.getString(MediaFormat.KEY_MIME)!!)
            dec = d
            d.configure(inFmt, null, null, 0)
            d.start()
            val m = MediaMuxer(out.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            mux = m

            // 1. compressed samples -> decoder
            spawn("demux") {
                while (true) {
                    check()
                    val i = d.dequeueInputBuffer(10_000)
                    if (i < 0) continue
                    val n = ex.readSampleData(d.getInputBuffer(i)!!, 0)
                    if (n < 0) {
                        d.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); return@spawn
                    }
                    d.queueInputBuffer(i, 0, n, ex.sampleTime, 0); ex.advance()
                }
            }

            // 2. decoder -> PCM -> effects -> queue
            spawn("fx") {
                var sr = inFmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                var ch = inFmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                var floatPcm = false
                var proc: TapeProcessor? = null
                val info = MediaCodec.BufferInfo()
                while (true) {
                    check()
                    val o = d.dequeueOutputBuffer(info, 10_000)
                    if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        val f = d.outputFormat
                        sr = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        ch = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        floatPcm = f.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                            f.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                    }
                    if (o < 0) continue
                    val buf = d.getOutputBuffer(o)!!
                    buf.position(info.offset); buf.limit(info.offset + info.size)
                    val mono = toMono(buf.slice().order(ByteOrder.nativeOrder()), info.size, ch, floatPcm)
                    d.releaseOutputBuffer(o, false)
                    (proc ?: TapeProcessor(sr, fx).also { proc = it }).process(mono)
                    val eos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    while (!q.offer(Pcm(sr, mono, eos), 20, TimeUnit.MILLISECONDS)) check()
                    if (eos) return@spawn
                }
            }

            // 3. queue -> encoder (created once the real sample rate is known)
            spawn("enc") {
                fun pull(): Pcm { while (true) { check(); q.poll(20, TimeUnit.MILLISECONDS)?.let { return it } } }
                val first = pull()
                val sr = first.sr
                val f = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sr, 1).apply {
                    setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                    setInteger(MediaFormat.KEY_BIT_RATE, 96_000)
                    setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16_384)
                }
                val e = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
                enc.set(e)
                e.configure(f, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE); e.start()

                // 4. encoder -> muxer
                spawn("mux") {
                    val info = MediaCodec.BufferInfo()
                    var track = -1
                    while (true) {
                        check()
                        val o = e.dequeueOutputBuffer(info, 10_000)
                        if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                            track = m.addTrack(e.outputFormat); m.start(); muxStarted.set(true)
                        }
                        if (o < 0) continue
                        val ob = e.getOutputBuffer(o)!!
                        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                        if (info.size > 0 && track >= 0) {
                            ob.position(info.offset); ob.limit(info.offset + info.size)
                            m.writeSampleData(track, ob, info)
                        }
                        e.releaseOutputBuffer(o, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) { done.set(true); return@spawn }
                    }
                }

                val pending = Chunks()
                pending.add(first.data)
                var eos = first.eos
                var fed = 0L
                while (true) {
                    while (!eos && pending.size < 8192) { val c = pull(); pending.add(c.data); eos = c.eos }
                    check()
                    val i = e.dequeueInputBuffer(10_000)
                    if (i < 0) continue
                    val ib = e.getInputBuffer(i)!!.order(ByteOrder.nativeOrder())
                    ib.clear()
                    val n = minOf(pending.size, ib.remaining() / 2)
                    pending.take(n, ib)
                    val last = eos && pending.size == 0
                    e.queueInputBuffer(i, 0, n * 2, fed * 1_000_000L / sr, if (last) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0)
                    fed += n
                    if (last) return@spawn
                }
            }

            while (threads.any { it.isAlive }) {
                if (cancelled()) abort.set(true)
                threads.firstOrNull { it.isAlive }?.join(20)
            }
            err.get()?.let { throw it }
            return done.get() && !abort.get()
        } finally {
            abort.set(true)
            threads.forEach { it.join(2_000) }
            runCatching { dec?.stop() }; runCatching { dec?.release() }
            enc.get()?.let { e -> runCatching { e.stop() }; runCatching { e.release() } }
            runCatching { if (muxStarted.get()) mux?.stop() }; runCatching { mux?.release() }
            ex.release()
        }
    }

    private fun toMono(buf: ByteBuffer, bytes: Int, ch: Int, float: Boolean): FloatArray {
        val c = ch.coerceAtLeast(1)
        return if (float) {
            val fb = buf.asFloatBuffer()
            FloatArray(bytes / 4 / c) { i -> var s = 0f; for (k in 0 until c) s += fb.get(i * c + k); s / c }
        } else {
            val sb = buf.asShortBuffer()
            FloatArray(bytes / 2 / c) { i -> var s = 0f; for (k in 0 until c) s += sb.get(i * c + k); s / c / 32768f }
        }
    }

    /** FIFO of float chunks, drained into 16-bit encoder buffers. */
    private class Chunks {
        private val q = ArrayDeque<FloatArray>()
        private var off = 0
        var size = 0; private set

        fun add(a: FloatArray) { if (a.isNotEmpty()) { q.addLast(a); size += a.size } }

        fun take(n: Int, out: ByteBuffer) {
            var left = n
            while (left > 0) {
                val a = q.first()
                val k = minOf(left, a.size - off)
                for (j in off until off + k) out.putShort((a[j].coerceIn(-1f, 1f) * 32767f).toInt().toShort())
                off += k; left -= k; size -= k
                if (off == a.size) { q.removeFirst(); off = 0 }
            }
        }
    }
}

/** Streaming, stateful tape-character processor (mono). */
class TapeProcessor(private val sr: Int, private val fx: TapeFx) {
    private val r = Random(1984)

    // wow & flutter: fractional delay line modulated by a few slow, incommensurate sines
    private val ring = FloatArray(16_384)
    private var w = 0

    // tone: rumble cut + gentle top roll-off, like a cheap mic and a worn head
    private val hp = Biquad.highpass(sr, 160.0, 0.7)
    private val lp1 = Biquad.lowpass(sr, 3400.0, 0.8)
    private val lp2 = Biquad.lowpass(sr, 5200.0, 0.6)
    private val mid = Biquad.peak(sr, 1300.0, 0.9, 2.5)

    // wow/flutter LFOs: wow is slow (~0.3 % pitch swing), flutter comes from the capstan
    private val wow1 = Osc(sr, 0.55); private val wow2 = Osc(sr, 0.23, .2)
    private val flut1 = Osc(sr, 6.3); private val flut2 = Osc(sr, 11.7, .1)

    // hiss + transport motor
    private var nLp = 0f; private var nLp2 = 0f
    private val hissLfo = Osc(sr, 0.5)
    private val motorLfo = Osc(sr, 0.7)
    private val hum = Osc(sr, 50.0)
    private var motorPh = 0.0

    fun process(x: FloatArray) {
        for (i in x.indices) x[i] = sample(x[i])
    }

    private fun sample(input: Float): Float {
        var v = input

        if (fx.wow) {
            ring[w] = v
            val delay = (0.006f + 0.00085f * wow1.next() + 0.00045f * wow2.next() +
                0.000026f * flut1.next() + 0.000012f * flut2.next()) * sr
            val pos = w - delay
            val i0 = kotlin.math.floor(pos).toInt()
            val frac = pos - i0
            val a = ring[i0 and MASK]; val b = ring[(i0 + 1) and MASK]
            v = a + (b - a) * frac
            w = (w + 1) and MASK
        }

        if (fx.saturate) v = fastTanh(3f * v) / 3f * 1.5f   // squashes peaks, lifts quiet bits

        if (fx.hiss) {
            val wn = r.nextFloat() * 2f - 1f
            nLp += 0.07f * (wn - nLp)
            nLp2 += 0.6f * ((wn - nLp) - nLp2)
            // transport motor: a faint buzzy whine that drifts with the motor speed
            motorPh += 118.0 * (1 + 0.012 * motorLfo.next()) / sr
            if (motorPh >= 1) motorPh -= 1
            val motor = BUZZ[(motorPh * TABLE).toInt() and (TABLE - 1)] * 0.0016f
            v += nLp2 * 0.016f * (1f + 0.2f * hissLfo.next()) + motor + 0.0018f * hum.next()
        }

        if (fx.muffle) v = mid.f(lp2.f(lp1.f(hp.f(v))))
        return v
    }

    /** Table-lookup sine oscillator (cheap enough to run several per sample). */
    private class Osc(sr: Int, hz: Double, phase: Double = 0.0) {
        private var ph = phase
        private val inc = hz / sr
        fun next(): Float {
            ph += inc; if (ph >= 1) ph -= 1
            return SINE[(ph * TABLE).toInt() and (TABLE - 1)]
        }
    }

    private companion object {
        const val MASK = 16_383
        const val TABLE = 4096
        val SINE = FloatArray(TABLE) { sin(2 * PI * it / TABLE).toFloat() }
        val BUZZ = FloatArray(TABLE) { tanh(3 * sin(2 * PI * it / TABLE)).toFloat() }
        fun fastTanh(x: Float): Float =
            if (x > 3f) 1f else if (x < -3f) -1f else x * (27f + x * x) / (27f + 9f * x * x)
    }
}

/** RBJ cookbook biquad. */
class Biquad private constructor(
    private val b0: Double, private val b1: Double, private val b2: Double,
    private val a1: Double, private val a2: Double,
) {
    private var z1 = 0.0
    private var z2 = 0.0

    fun f(x: Float): Float {
        val y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y.toFloat()
    }

    companion object {
        private fun make(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) =
            Biquad(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)

        fun lowpass(sr: Int, f: Double, q: Double): Biquad {
            val w = 2 * PI * f / sr; val cs = cos(w); val al = sin(w) / (2 * q)
            return make((1 - cs) / 2, 1 - cs, (1 - cs) / 2, 1 + al, -2 * cs, 1 - al)
        }

        fun highpass(sr: Int, f: Double, q: Double): Biquad {
            val w = 2 * PI * f / sr; val cs = cos(w); val al = sin(w) / (2 * q)
            return make((1 + cs) / 2, -(1 + cs), (1 + cs) / 2, 1 + al, -2 * cs, 1 - al)
        }

        fun peak(sr: Int, f: Double, q: Double, db: Double): Biquad {
            val a = Math.pow(10.0, db / 40); val w = 2 * PI * f / sr; val cs = cos(w); val al = sin(w) / (2 * q)
            return make(1 + al * a, -2 * cs, 1 - al * a, 1 + al / a, -2 * cs, 1 - al / a)
        }
    }
}
