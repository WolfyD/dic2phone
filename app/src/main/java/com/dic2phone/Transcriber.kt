package com.dic2phone

import androidx.annotation.StringRes
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteOrder
import java.security.MessageDigest
import javax.crypto.SecretKey
import kotlin.math.sqrt

/**
 * Captions, made on the phone with whisper.cpp. Tapes are decoded to 16 kHz mono, fed to the
 * model in ~5 minute pieces cut at the quietest moment, and the result saved as .srt.
 * The speech model is downloaded once (from Hugging Face) the first time captions are asked for.
 */
object Transcriber {
    private const val TAG = "Transcriber"
    private const val SR = 16_000
    private const val PIECE = SR * 300          // 5 minutes
    private const val SEARCH = SR * 30          // look for a quiet cut point in the last 30 s

    enum class Model(val id: String, val label: String, val file: String, val sha256: String, val bytes: Long, val size: String, @StringRes val note: Int) {
        BASE(
            "base", "BASE", "ggml-base-q5_1.bin",
            "422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898", 59_707_625,
            "57 MB", R.string.model_note_base
        ),
        SMALL(
            "small", "SMALL", "ggml-small-q5_1.bin",
            "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb", 190_085_487,
            "181 MB", R.string.model_note_small
        );

        val url get() = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$file"

        companion object { fun byId(id: String) = entries.firstOrNull { it.id == id } }
    }

    fun modelDir(ctx: Context) = File(ctx.filesDir, "whisper")
    fun modelFile(ctx: Context, m: Model) = File(modelDir(ctx), m.file)
    fun installed(ctx: Context, m: Model) = modelFile(ctx, m).length() == m.bytes
    fun deleteModels(ctx: Context) { modelDir(ctx).deleteRecursively() }

    /** null when idle. */
    data class Status(val tapeId: String?, val line: String, val pct: Int, val index: Int, val total: Int)

    private val _status = MutableStateFlow<Status?>(null)
    val status: StateFlow<Status?> = _status
    private val _queued = MutableStateFlow<Set<String>>(emptySet())
    /** Tapes waiting for or getting captions. */
    val queued: StateFlow<Set<String>> = _queued
    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError

    /** A tape to caption, or (tape == null) just a speech model to fetch. */
    private class Work(val tape: Tape?, val key: SecretKey?, val fetch: Model? = null)

    /** Id in [queued] while [m] is waiting to be / being downloaded. */
    fun fetchId(m: Model) = "model:${m.id}"

    /** Downloads [m] in the background (same queue and notification as captions). */
    fun fetch(ctx: Context, m: Model) {
        if (installed(ctx, m) || fetchId(m) in _queued.value) return
        synchronized(queue) { queue.addLast(Work(null, null, m)) }
        _queued.value = _queued.value + fetchId(m)
        _lastError.value = null
        ContextCompat.startForegroundService(ctx, Intent(ctx, TranscribeService::class.java))
    }
    private val queue = ArrayDeque<Work>()
    private var done = 0
    @Volatile private var cancelled = false
    @Volatile private var model: Whisper.Model? = null

    /** @return false if the work couldn't start (Android refused a background start); nothing is queued then. */
    fun enqueue(ctx: Context, tapes: List<Tape>): Boolean {
        val add = tapes.filter { it.id !in _queued.value }
        if (add.isEmpty()) return true
        val works = add.map { Work(it, if (it.vault != null) Vault.currentKey() else null) }
        synchronized(queue) { works.forEach { queue.addLast(it) } }
        _queued.value = _queued.value + add.map { it.id }
        _lastError.value = null
        return try {
            ContextCompat.startForegroundService(ctx, Intent(ctx, TranscribeService::class.java))
            true
        } catch (e: Exception) {
            Log.w(TAG, "couldn't start captions", e)
            synchronized(queue) { queue.removeAll(works.toSet()) }
            _queued.value = _queued.value - add.map { it.id }.toSet()
            false
        }
    }

    fun cancelAll() {
        cancelled = true
        synchronized(queue) { queue.clear() }
        model?.cancel()
    }

    private fun total() = done + synchronized(queue) { queue.size } + 1

    /** Runs the queue to the end. Called by [TranscribeService] on a background thread. */
    internal suspend fun run(ctx: Context, onStatus: (Status) -> Unit) {
        cancelled = false
        done = 0
        var loaded: Model? = null
        try {
            while (!cancelled) {
                val w = synchronized(queue) { queue.removeFirstOrNull() } ?: break
                val f = w.fetch
                if (w.tape == null && f != null) {
                    try {
                        if (!installed(ctx, f)) download(ctx, f) { pct ->
                            Status(null, L.s(R.string.cc_fetching, f.label), pct, done + 1, total()).also { _status.value = it; onStatus(it) }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "fetch ${f.id}", e)
                        _lastError.value = e.message ?: e.javaClass.simpleName
                    }
                    done++
                    _queued.value = _queued.value - fetchId(f)
                    continue
                }
                val t = w.tape ?: continue
                fun status(line: String, pct: Int) =
                    Status(t.id, line, pct, done + 1, total()).also { _status.value = it; onStatus(it) }
                try {
                    val m = Model.byId(Prefs.ccModel.value) ?: Model.BASE
                    if (!installed(ctx, m)) download(ctx, m) { status(L.s(R.string.cc_fetching, m.label), it) }
                    if (cancelled) break
                    if (loaded != m || model == null) {
                        status(L.s(R.string.cc_loading), 0)
                        model?.close(); model = null
                        model = Whisper.Model.load(modelFile(ctx, m).path) ?: error(L.s(R.string.cc_err_load))
                        loaded = m
                    }
                    status(L.s(R.string.cc_listening), 0)
                    val cues = transcribe(ctx, w, model!!, Prefs.ccLang.value) { status(L.s(R.string.cc_listening), it) }
                    if (cues != null && !cancelled) save(ctx, w, cues)
                } catch (e: Exception) {
                    Log.e(TAG, "caption ${t.id}", e)
                    _lastError.value = e.message ?: e.javaClass.simpleName
                }
                done++
                _queued.value = _queued.value - t.id
            }
        } finally {
            model?.close(); model = null
            synchronized(queue) { queue.clear() }
            _queued.value = emptySet()
            _status.value = null
        }
    }

    private fun save(ctx: Context, w: Work, cues: List<Cue>) {
        val srt = Captions.toSrt(cues)
        val t = w.tape!!
        if (t.vault != null) {
            Vault.writeCaption(ctx, t.vault, srt, w.key ?: error("vault was locked"))
        } else {
            val f = Captions.file(ctx, t.id)
            val tmp = File(f.parentFile, f.name + ".part")
            tmp.writeText(srt)
            f.replaceWith(tmp)
        }
        TapeStore.bump()
    }

    // ---- Model download -------------------------------------------------------------------

    private fun download(ctx: Context, m: Model, progress: (Int) -> Unit) {
        val out = modelFile(ctx, m)
        out.parentFile!!.mkdirs()
        val tmp = File(out.parentFile, out.name + ".part")
        val md = MessageDigest.getInstance("SHA-256")
        val c = URL(m.url).openConnection() as HttpURLConnection
        c.instanceFollowRedirects = true
        c.connectTimeout = 20_000
        c.readTimeout = 30_000
        c.setRequestProperty("User-Agent", "Dic2Phone")
        try {
            if (c.responseCode != 200) error(L.s(R.string.cc_err_http, c.responseCode))
            var got = 0L
            var lastPct = -1
            c.inputStream.use { inp ->
                tmp.outputStream().use { o ->
                    val buf = ByteArray(256 * 1024)
                    while (true) {
                        if (cancelled) return
                        val n = inp.read(buf)
                        if (n < 0) break
                        o.write(buf, 0, n); md.update(buf, 0, n)
                        got += n
                        if (got > m.bytes) error(L.s(R.string.cc_err_corrupt))
                        val pct = (got * 100 / m.bytes).toInt()
                        if (pct != lastPct) { lastPct = pct; progress(pct) }
                    }
                }
            }
            val sha = md.digest().joinToString("") { "%02x".format(it) }
            if (got != m.bytes || sha != m.sha256) error(L.s(R.string.cc_err_corrupt))
            if (!tmp.renameTo(out)) error(L.s(R.string.cc_err_save))
        } finally {
            c.disconnect()
            tmp.delete()
        }
    }

    // ---- Audio -> text ------------------------------------------------------------------------

    private fun transcribe(ctx: Context, w: Work, model: Whisper.Model, lang: String, progress: (Int) -> Unit): List<Cue>? {
        val t = w.tape!!
        val cues = mutableListOf<Cue>()
        val expected = (t.durationMs * SR / 1000).coerceAtLeast(1)
        val threads = Runtime.getRuntime().availableProcessors().coerceIn(1, 4)
        var buf = FloatArray(PIECE + SEARCH)
        var n = 0
        var offset = 0L   // samples already sent
        var ok = true

        fun feed(len: Int) {
            val piece = buf.copyOf(len)
            if (rms(piece, 0, len) > 0.002f) {   // skip near-silent pieces (whisper hallucinates on silence)
                val base = offset
                val job = Thread {
                    // Report progress while whisper works.
                    while (!Thread.currentThread().isInterrupted) {
                        progress(((base + len.toLong() * model.progress / 100) * 100 / expected).toInt().coerceIn(0, 99))
                        try { Thread.sleep(500) } catch (_: InterruptedException) { break }
                    }
                }.apply { start() }
                val segs = try { model.transcribe(piece, lang, threads) } finally { job.interrupt() }
                if (segs == null) { ok = false; return }
                val offMs = offset * 1000 / SR
                segs.forEach { s ->
                    val text = s.text.replace('�', ' ').trim()
                    if (text.isNotEmpty()) cues += Cue(offMs + s.startMs, offMs + s.endMs, text)
                }
            }
            offset += len
            System.arraycopy(buf, len, buf, 0, n - len)
            n -= len
        }

        decode16k(ctx, t, w.key) { chunk ->
            if (cancelled || !ok) return@decode16k false
            if (n + chunk.size > buf.size) buf = buf.copyOf(maxOf(buf.size * 2, n + chunk.size))
            System.arraycopy(chunk, 0, buf, n, chunk.size)
            n += chunk.size
            if (n >= PIECE + SEARCH) feed(quietCut(buf, PIECE, PIECE + SEARCH))
            !cancelled && ok
        }
        if (cancelled || !ok) return null
        if (n > SR / 4) feed(n)
        progress(100)
        return cues
    }

    /** Index of the quietest 100 ms window in [from, to). */
    private fun quietCut(a: FloatArray, from: Int, to: Int): Int {
        val win = SR / 10
        var best = from; var bestE = Float.MAX_VALUE
        var i = from
        while (i + win <= to) {
            val e = rms(a, i, win)
            if (e < bestE) { bestE = e; best = i + win / 2 }
            i += win / 2
        }
        return best
    }

    private fun rms(a: FloatArray, off: Int, len: Int): Float {
        var s = 0.0
        for (i in off until off + len) s += a[i] * a[i]
        return sqrt(s / len.coerceAtLeast(1)).toFloat()
    }

    /** Decodes a tape to 16 kHz mono float PCM, handing it over in chunks. [sink] returns false to stop. */
    internal fun decode16k(ctx: Context, t: Tape, key: SecretKey?, sink: (FloatArray) -> Boolean) {
        val ex = MediaExtractor()
        var dec: MediaCodec? = null
        try {
            if (t.vault != null) ex.setDataSource(Vault.source(ctx, t, key) ?: error("vault was locked"))
            else ex.setDataSource(ctx, t.uri, null)
            val ti = (0 until ex.trackCount).firstOrNull {
                ex.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: error("no audio in tape")
            ex.selectTrack(ti)
            val fmt = ex.getTrackFormat(ti)
            val d = MediaCodec.createDecoderByType(fmt.getString(MediaFormat.KEY_MIME)!!)
            dec = d
            d.configure(fmt, null, null, 0)
            d.start()
            var sr = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var ch = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var floatPcm = false
            var rs: Resampler? = null
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            while (true) {
                if (!inputDone) {
                    val i = d.dequeueInputBuffer(5_000)
                    if (i >= 0) {
                        val sz = ex.readSampleData(d.getInputBuffer(i)!!, 0)
                        if (sz < 0) { d.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); inputDone = true }
                        else { d.queueInputBuffer(i, 0, sz, ex.sampleTime, 0); ex.advance() }
                    }
                }
                val o = d.dequeueOutputBuffer(info, 5_000)
                if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val f = d.outputFormat
                    sr = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    ch = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    floatPcm = f.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                        f.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                    rs = null
                }
                if (o < 0) continue
                val buf = d.getOutputBuffer(o)!!
                buf.position(info.offset); buf.limit(info.offset + info.size)
                val b = buf.slice().order(ByteOrder.nativeOrder())
                val c = ch.coerceAtLeast(1)
                val mono = if (floatPcm) {
                    val fb = b.asFloatBuffer()
                    FloatArray(info.size / 4 / c) { i -> var s = 0f; for (k in 0 until c) s += fb.get(i * c + k); s / c }
                } else {
                    val sb = b.asShortBuffer()
                    FloatArray(info.size / 2 / c) { i -> var s = 0f; for (k in 0 until c) s += sb.get(i * c + k); s / c / 32768f }
                }
                d.releaseOutputBuffer(o, false)
                val r = rs ?: Resampler(sr).also { rs = it }
                if (mono.isNotEmpty() && !sink(r.process(mono))) return
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
            }
        } finally {
            runCatching { dec?.stop() }; runCatching { dec?.release() }
            ex.release()
        }
    }

    /** Low-pass + linear interpolation down to 16 kHz. Plenty for speech recognition. */
    private class Resampler(private val inRate: Int) {
        private val step = inRate.toDouble() / SR
        private val lp1 = if (inRate > SR * 1.1) Biquad.lowpass(inRate, 7200.0, 0.54) else null
        private val lp2 = if (inRate > SR * 1.1) Biquad.lowpass(inRate, 7200.0, 1.31) else null
        private var pos = 0.0
        private var prev = 0f

        fun process(x: FloatArray): FloatArray {
            val out = FloatArray((x.size / step).toInt() + 2)
            var n = 0
            for (v0 in x) {
                var v = v0
                if (lp1 != null) v = lp2!!.f(lp1.f(v))
                while (pos < 1.0) {
                    out[n++] = prev + (v - prev) * pos.toFloat()
                    pos += step
                }
                pos -= 1.0
                prev = v
            }
            return out.copyOf(n)
        }
    }
}

/** Keeps the process alive (and the CPU awake) while captions are being made. */
class TranscribeService : Service() {
    companion object {
        private const val CH = "captions"
        private const val ID = 3
        private const val ACTION_CANCEL = "com.dic2phone.CC_CANCEL"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var job: Job? = null
    private var wake: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CH, L.s(R.string.cc_channel), NotificationManager.IMPORTANCE_LOW).apply {
                setSound(null, null); description = L.s(R.string.cc_channel_desc)
            }
        )
        ServiceCompat.startForeground(
            this, ID, notification(null),
            if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0
        )
        if (intent?.action == ACTION_CANCEL) {
            Transcriber.cancelAll()
            return START_NOT_STICKY
        }
        if (job?.isActive != true) {
            wake = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "dic2phone:captions").apply { acquire(6 * 3600_000L) }
            job = scope.launch {
                var last = 0L
                try {
                    Transcriber.run(applicationContext) { s ->
                        val now = System.currentTimeMillis()
                        if (now - last > 1000) { last = now; nm.notify(ID, notification(s)) }
                    }
                    delay(50)
                } finally {
                    wake?.let { if (it.isHeld) it.release() }
                    ServiceCompat.stopForeground(this@TranscribeService, ServiceCompat.STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        Transcriber.cancelAll()
    }

    override fun onDestroy() {
        Transcriber.cancelAll()
        scope.cancel()
        wake?.let { if (it.isHeld) it.release() }
        super.onDestroy()
    }

    private fun notification(s: Transcriber.Status?): Notification {
        val cancel = PendingIntent.getService(
            this, 1, Intent(this, TranscribeService::class.java).setAction(ACTION_CANCEL),
            PendingIntent.FLAG_IMMUTABLE
        )
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CH)
            .setSmallIcon(R.drawable.ic_cassette)
            .setContentTitle(
                when {
                    s == null -> L.s(R.string.cc_channel)
                    s.tapeId == null -> L.s(R.string.cc_notif_model)
                    else -> L.s(R.string.cc_notif_tape, s.index, s.total)
                }
            )
            .setContentText(s?.let { "${it.line} · ${it.pct}%" } ?: L.s(R.string.cc_notif_starting))
            .setProgress(100, s?.pct ?: 0, s == null)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setContentIntent(open)
            .addAction(0, L.s(R.string.cc_notif_cancel), cancel)
            .build()
    }
}
