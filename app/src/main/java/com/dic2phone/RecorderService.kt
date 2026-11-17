package com.dic2phone

import android.Manifest
import android.app.NotificationManager
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.service.quicksettings.TileService
import android.util.Log
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import java.io.File
import kotlin.math.log10

object Recorder {
    data class State(
        val recording: Boolean = false,
        val startedAt: Long = 0L,      // SystemClock.elapsedRealtime()
        val level: Float = 0f,         // 0..1 VU level
        val error: String? = null,
        /** Stays on by itself (triple tap / quick tap on REC) until stopped. */
        val latched: Boolean = false,
        /** Noise-activated: the tape only moves while there's sound. */
        val vox: Boolean = false,
        /** The tape is moving (always, unless noise-activated and it's quiet). */
        val rolling: Boolean = true,
        /** Length of the current tape so far (skipped silences don't count). */
        val tapeMs: Long = 0L,
        /** Flags set on the current tape. */
        val flags: Int = 0,
        /** Which tape of a long session (rolls onto a new tape every hour). */
        val part: Int = 0,
    ) {
        /** The reels turn: recording, and not idling on silence under noise activation. */
        val tapeMoving: Boolean get() = recording && (!vox || rolling)
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state
    internal fun set(s: State) { _state.value = s }
    internal fun update(f: (State) -> State) = _state.update(f)
}

/**
 * Foreground service that runs the tape transport ([TapeEngine]) and writes down what it
 * recorded ([TapeMeta]). Control calls arrive on the main thread (UI, accessibility service,
 * tile); engine events are posted back to it, so no locking is needed here.
 */
class RecorderService : Service() {

    companion object {
        private const val TAG = "RecorderService"
        private const val ACTION_START = "com.dic2phone.START"
        const val ACTION_STOP = "com.dic2phone.STOP"
        private const val MIN_TAPE_MS = 700L

        private var instance: RecorderService? = null
        /** Set by stop(); a START that arrives after it is aborted (very quick tap). */
        private var stopRequested = false
        private var startLatched = false

        /**
         * @param source who triggered it (kept in the tape's metadata).
         * @param latched start locked on, instead of recording only while held.
         */
        fun start(ctx: Context, source: String, latched: Boolean = false) {
            if (Recorder.state.value.recording) return
            Log.i(TAG, "start requested by $source")
            stopRequested = false
            startLatched = latched
            val i = Intent(ctx, RecorderService::class.java).setAction(ACTION_START).putExtra("source", source)
            try {
                ContextCompat.startForegroundService(ctx, i)
            } catch (e: Exception) {
                Log.e(TAG, "startForegroundService failed", e)
                Recorder.set(Recorder.State(error = L.s(R.string.err_start, e.javaClass.simpleName)))
            }
        }

        fun stop() {
            stopRequested = true
            instance?.end()
        }

        /** Keep the recording going after the key is let go. */
        fun latch() {
            val s = instance?.cur
            // Not started yet (the service is still coming up): start it locked.
            if (s == null) { if (!stopRequested) startLatched = true } else instance?.latch(s)
        }

        /** Flag this moment on the tape being recorded. */
        fun flag() { instance?.cur?.engine?.flag() }
    }

    /** One press of REC until STOP; may produce several tapes (hour splits). */
    private inner class Session(val source: String) : TapeEngine.Events {
        var latched = false
        var engine: TapeEngine? = null
        val wallStart = System.currentTimeMillis()
        var location: Location? = null
        var place = ""
        var kept = 0
        var silent = false
        var failed: String? = null
        /** Tapes written so far, so a late location fix can still be added. */
        val saved = mutableListOf<Tape>()

        override fun onTapeStarted(file: File, part: Int) {
            h.post { if (cur === this) { Recorder.update { it.copy(part = part, flags = 0) }; refreshNotif() } }
        }
        override fun onFlag(count: Int) {
            h.post {
                Feedback.flag(this@RecorderService)
                if (cur === this) { Recorder.update { it.copy(flags = count) }; refreshNotif() }
            }
        }
        override fun onTapeDone(d: TapeEngine.Done) { h.post { saveTape(this, d) } }
        override fun onFailed(msg: String) {
            h.post {
                failed = msg
                if (cur === this) end()
            }
        }
        override fun onFinished() { h.post { finished(this) } }
    }

    private var cur: Session? = null
    /** Sessions stopped but still closing their last tape. */
    private var closing = 0
    private var wakeLock: PowerManager.WakeLock? = null
    private val h = Handler(Looper.getMainLooper())
    private var notifKey: Any? = null

    private val beginEngine = Runnable { cur?.let(::startEngine) }
    private val notifTick = object : Runnable {
        override fun run() {
            if (cur == null) return
            refreshNotif()
            h.postDelayed(this, 1000)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /** The phone is switching off (or the battery is out): close the tape properly while we can. */
    private val powerOff = object : android.content.BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            Log.i(TAG, "phone shutting down: stopping the tape")
            stopRequested = true
            end()
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        runCatching {
            ContextCompat.registerReceiver(
                this, powerOff, android.content.IntentFilter(Intent.ACTION_SHUTDOWN), ContextCompat.RECEIVER_EXPORTED
            )
        }.onFailure { Log.w(TAG, "shutdown receiver", it) }
    }

    override fun onDestroy() {
        runCatching { unregisterReceiver(powerOff) }
        cur?.engine?.stopNow = true
        cur = null
        h.removeCallbacksAndMessages(null)
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> begin(intent.getStringExtra("source") ?: "?")
            ACTION_STOP -> { stopRequested = true; end() }
        }
        return START_NOT_STICKY
    }

    private fun begin(source: String) {
        val loc = Where.wanted(this)
        // Must always call startForeground after startForegroundService, even if we abort.
        val fgOk = startFg(loc) || (loc && startFg(false))
        if (!fgOk) {
            Recorder.set(Recorder.State(error = L.s(R.string.err_bg_mic)))
            if (cur == null && closing == 0) shutdown()
            return
        }
        if (stopRequested || cur != null) {
            if (cur == null && closing == 0) shutdown()
            return
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Recorder.set(Recorder.State(error = L.s(R.string.err_perm)))
            if (closing == 0) shutdown()
            return
        }

        Player.stop()   // the deck can't play and record at once
        val s = Session(source)
        s.latched = startLatched
        startLatched = false
        cur = s
        Feedback.recStart(this)
        if (wakeLock == null) wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "dic2phone:rec")
            .apply { acquire(24 * 3600_000L) }
        Recorder.set(
            Recorder.State(
                recording = true, startedAt = SystemClock.elapsedRealtime(),
                latched = s.latched, vox = s.latched && Prefs.vox.value, rolling = !(s.latched && Prefs.vox.value),
            )
        )
        if (s.latched) Feedback.latch(this)
        refreshTile()
        refreshNotif()
        h.post(notifTick)
        if (loc) findPlace(s)
        // Let the key click finish so it isn't recorded.
        h.postDelayed(beginEngine, Feedback.START_SOUND_MS)
    }

    private fun startFg(location: Boolean): Boolean = try {
        var type = if (Build.VERSION.SDK_INT >= 30) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0
        if (location && Build.VERSION.SDK_INT >= 29) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
        ServiceCompat.startForeground(this, Notifs.ID_REC, Notifs.recording(this), type)
        true
    } catch (e: Exception) {
        Log.e(TAG, "startForeground (location=$location) failed", e)
        false
    }

    private fun startEngine(s: Session) {
        if (s.engine != null) return
        val e = TapeEngine(
            this, gated = s.latched && Prefs.vox.value, snap = Prefs.snap.value, voxSens = Prefs.voxSens.value,
            maxTapeMs = Prefs.maxTapeSec * 1000L, events = s,
        )
        s.engine = e
        e.start()
        Feedback.hissStart(this)
    }

    private fun latch(s: Session) {
        if (s.latched) return
        s.latched = true
        val vox = Prefs.vox.value
        s.engine?.gated = vox
        Recorder.update { it.copy(latched = true, vox = vox) }
        Feedback.latch(this)
        refreshTile()
        refreshNotif()
        Log.i(TAG, "latched (vox=$vox)")
    }

    /** Stop recording; the engine closes the tape and reports back in [finished]. */
    fun end() {
        h.removeCallbacks(beginEngine)
        h.removeCallbacks(notifTick)
        val s = cur ?: run { if (closing == 0) shutdown(); return }
        cur = null
        Feedback.hissStop()
        Recorder.set(Recorder.State())
        refreshTile()
        val e = s.engine
        if (e == null) {
            // Stopped before the tape started moving: nothing recorded.
            Feedback.recStop(this)
            if (closing == 0) shutdown()
            return
        }
        closing++
        e.stopNow = true
    }

    private fun finished(s: Session) {
        closing--
        // Played only now, after the mic has been closed, so the clack isn't on the tape.
        Feedback.recStop(this)
        val err = when {
            s.failed != null -> s.failed
            s.silent -> L.s(R.string.err_silent)
            s.kept == 0 && s.engine?.gated == true -> L.s(R.string.err_nothing)
            else -> null
        }
        if (err != null && cur == null) Recorder.update { it.copy(error = err) }
        runCatching { AutoCaptions.recorded(this, s.saved.filter { it.file?.exists() == true }) }
            .onFailure { Log.w(TAG, "auto captions", it) }
        if (s.kept > 0) runCatching { FxPrep.sync(this) }   // new tapes want effects copies
        if (cur == null && closing <= 0) shutdown()
    }

    // ---- Writing down what was recorded -----------------------------------------------------

    private fun saveTape(s: Session, d: TapeEngine.Done) {
        val f = d.file
        val peakDb = 20 * log10(d.peak.coerceAtLeast(1) / 32767f)
        if (!d.ok || d.durationMs < MIN_TAPE_MS) {
            f.delete()
            Log.i(TAG, "discarded ${f.name} (${d.durationMs}ms, ok=${d.ok}, peak=${"%.1f".format(peakDb)}dB)")
            return
        }
        Log.i(TAG, "saved ${f.name} (${d.durationMs}ms, part ${d.part}, ${d.flags.size} flags, ${d.cuts} cuts, peak=${"%.1f".format(peakDb)}dB)")
        // Another app holding the mic (or a privacy toggle) gives digital silence.
        if (d.durationMs > 2000 && d.peak < 8) s.silent = true
        s.kept++
        val loc = s.location
        val m = TapeMeta(
            startedAt = d.startWall, endedAt = d.endWall, durationMs = d.durationMs, sizeBytes = f.length(),
            format = TapeMeta.FORMAT, peakDb = peakDb, avgDb = d.rmsDb,
            source = if (d.part > 1) "split" else s.source, device = TapeMeta.DEVICE,
            latched = s.latched, vox = d.vox, cuts = d.cuts, skippedMs = d.skippedMs,
            part = if (d.part > 1) d.part else 0,
            lat = loc?.latitude, lon = loc?.longitude, accuracyM = loc?.takeIf { it.hasAccuracy() }?.accuracy,
            place = s.place, flags = d.flags,
        )
        val t = Tape(f.name, Uri.fromFile(f), f, d.durationMs, f.length(), isNew = true)
        MetaStore.save(this, t, m)
        // The first hour of a long session only now turns out to be "part 1".
        if (d.part == 2) s.saved.firstOrNull()?.let { first -> MetaStore.update(this, first) { it.copy(part = 1) } }
        s.saved += t
        Notifs.showNewTapes(this, TapeStore.newCount(this), f.name)
    }

    /** One location fix per session, written onto its tapes (also those already finished). */
    private fun findPlace(s: Session) {
        Where.fix(this) { l ->
            if (l == null) { Log.i(TAG, "no location fix"); return@fix }
            s.location = l
            patchPlace(s)
            Where.placeName(this, l.latitude, l.longitude) { name ->
                if (!name.isNullOrBlank()) { s.place = name; patchPlace(s) }
            }
        }
    }

    private fun patchPlace(s: Session) {
        val l = s.location ?: return
        s.saved.forEach { t ->
            if (t.file?.exists() != true) return@forEach   // shelved / deleted meanwhile: leave it
            MetaStore.update(this, t) {
                it.copy(lat = l.latitude, lon = l.longitude, accuracyM = l.takeIf { x -> x.hasAccuracy() }?.accuracy, place = s.place)
            }
        }
    }

    // ---- Plumbing --------------------------------------------------------------------------

    private fun refreshNotif() {
        val r = Recorder.state.value
        if (!r.recording) return
        val key = listOf(r.latched, r.vox, r.rolling, r.flags, r.part)
        if (key == notifKey) return
        notifKey = key
        val since = System.currentTimeMillis() - (SystemClock.elapsedRealtime() - r.startedAt)
        runCatching {
            getSystemService(NotificationManager::class.java).notify(
                Notifs.ID_REC, Notifs.recording(this, r.latched, r.vox, r.rolling, since, r.flags, r.part)
            )
        }
    }

    private fun shutdown() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        notifKey = null
        if (Recorder.state.value.recording) Recorder.set(Recorder.State())
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
        refreshTile()
    }

    private fun refreshTile() {
        runCatching {
            TileService.requestListeningState(this, ComponentName(this, RecordTileService::class.java))
        }
    }
}
