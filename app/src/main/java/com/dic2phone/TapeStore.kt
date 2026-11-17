package com.dic2phone

import android.content.ClipData
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.media.PlaybackParams
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.MediaStore
import android.util.Log
import androidx.core.content.FileProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

data class Tape(
    val id: String,          // file / display name, e.g. 2026-11-16_03-12-45.m4a
    val uri: Uri,
    val file: File?,         // set for deck tapes, null for shelf (MediaStore) tapes
    val durationMs: Long,
    val sizeBytes: Long,
    val isNew: Boolean,
    val vault: String? = null,   // sealed file name when the tape is locked in the vault
    val cc: Boolean = false,     // has captions
    val title: String = "",      // the user's title, from the tape's metadata
) {
    /** What goes on the cassette label: the title, else the date. */
    val label: String get() = title.ifBlank { pretty }
    val pretty: String get() = TapeNames.pretty(id)
    val date: String get() = TapeNames.date(id)
    val time: String get() = TapeNames.time(id)
}

object TapeNames {
    private val fileFmt get() = SimpleDateFormat("yyyy-MM-dd_HH-mm-ss", Locale.US)

    fun newBase(): String = fileFmt.format(Date())

    private fun parse(name: String): Date? =
        runCatching { fileFmt.parse(name.substringBefore('.').take(19)) }.getOrNull()

    fun date(name: String): String =
        parse(name)?.let { d -> L.locale().let { SimpleDateFormat("dd MMM yyyy", it).format(d).uppercase(it) } } ?: name

    fun time(name: String): String =
        parse(name)?.let { SimpleDateFormat("HH:mm:ss", Locale.US).format(it) } ?: ""

    fun pretty(name: String) = "${date(name)}  ${time(name)}".trim()

    fun duration(ms: Long): String {
        val s = (ms + 500) / 1000
        return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, (s / 60) % 60, s % 60)
        else "%d:%02d".format(s / 60, s % 60)
    }
}

object TapeStore {
    private const val TAG = "TapeStore"
    private const val PREFS = "tapes"
    private const val KEY_HEARD = "heard"

    private val _version = MutableStateFlow(0)
    /** Bumped whenever tapes change, so UI reloads. */
    val version: StateFlow<Int> = _version
    fun bump() { _version.value++ }

    private val durations = ConcurrentHashMap<String, Long>()

    /** Held while a tape file is rewritten (tags) or moved, so the two never overlap. */
    val io = Any()

    val shelfRelPath: String
        get() = (if (Build.VERSION.SDK_INT >= 31) Environment.DIRECTORY_RECORDINGS
        else Environment.DIRECTORY_MUSIC) + "/Dic2Phone/"

    fun deckDir(ctx: Context): File =
        File(ctx.getExternalFilesDir(null) ?: ctx.filesDir, "deck").apply { mkdirs() }

    fun newTapeFile(ctx: Context): File {
        val dir = deckDir(ctx)
        val base = TapeNames.newBase()
        var f = File(dir, "$base.m4a")
        var n = 2
        while (f.exists()) f = File(dir, "${base}_${n++}.m4a")
        return f
    }

    // ---- "new" (unheard) tracking --------------------------------------------------------

    private fun heard(ctx: Context): Set<String> =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getStringSet(KEY_HEARD, emptySet())!!

    fun markHeard(ctx: Context, ids: Collection<String>) {
        if (ids.isEmpty()) return
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        p.edit().putStringSet(KEY_HEARD, HashSet(heard(ctx)) + ids).apply()
        bump()
    }

    fun markAllHeard(ctx: Context) {
        markHeard(ctx, deckFiles(ctx).map { it.name })
        Notifs.clearNewTapes(ctx)
    }

    private fun forget(ctx: Context, ids: Collection<String>) {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        p.edit().putStringSet(KEY_HEARD, HashSet(heard(ctx)) - ids.toSet()).apply()
    }

    fun newCount(ctx: Context): Int {
        val h = heard(ctx)
        return deckFiles(ctx).count { it.name !in h }
    }

    // ---- Deck (app storage) ---------------------------------------------------------------

    private fun deckFiles(ctx: Context): List<File> =
        deckDir(ctx).listFiles { f -> f.isFile && f.extension == "m4a" }.orEmpty()
            .sortedByDescending { it.name }

    fun deck(ctx: Context): List<Tape> {
        val h = heard(ctx)
        return deckFiles(ctx).map { f ->
            Tape(
                id = f.name,
                uri = Uri.fromFile(f),
                file = f,
                durationMs = durationOf(f),
                sizeBytes = f.length(),
                isNew = f.name !in h,
                cc = Captions.file(ctx, f.name).exists(),
                title = MetaStore.loadPlain(ctx, f.name)?.title.orEmpty(),
            )
        }
    }

    private fun durationOf(f: File): Long = durations.getOrPut("${f.path}:${f.length()}") {
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(f.path)
            r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
        } catch (e: Exception) {
            0L
        } finally {
            r.release()
        }
    }

    /** @return how many tapes could not be removed. */
    fun delete(ctx: Context, tapes: Collection<Tape>): Int {
        val (locked, plain) = tapes.partition { it.vault != null }
        if (locked.isNotEmpty()) Vault.erase(ctx, locked)
        var failed = 0
        plain.forEach { t ->
            if (Player.playingId.value == t.id) Player.stop()
            if (Player.loaded.value?.id == t.id) Player.eject()
            val ok = synchronized(io) {
                if (t.file != null) t.file.delete() || !t.file.exists()
                else runCatching { ctx.contentResolver.delete(t.uri, null, null) > 0 }
                    .onFailure { Log.w(TAG, "delete ${t.uri}", it) }.getOrDefault(false)
            }
            if (ok) { Captions.delete(ctx, t.id); MetaStore.delete(ctx, t.id) } else failed++
        }
        forget(ctx, plain.map { it.id })
        runCatching { LoFi.forget(ctx, plain.map { it.id }) }
        bump()
        Notifs.showNewTapes(ctx, newCount(ctx), null)
        return failed
    }

    fun wipeDeck(ctx: Context) = delete(ctx, deck(ctx))

    // ---- Shelf (public Recordings/Dic2Phone via MediaStore; survives uninstall) ------------

    private val audioCollection: Uri
        get() = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)

    fun shelf(ctx: Context): List<Tape> {
        val out = mutableListOf<Tape>()
        val proj = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.SIZE,
        )
        try {
            ctx.contentResolver.query(
                audioCollection, proj,
                "${MediaStore.Audio.Media.RELATIVE_PATH} = ?", arrayOf(shelfRelPath),
                "${MediaStore.Audio.Media.DISPLAY_NAME} DESC"
            )?.use { c ->
                while (c.moveToNext()) {
                    val id = c.getLong(0)
                    out += Tape(
                        id = c.getString(1),
                        uri = ContentUris.withAppendedId(audioCollection, id),
                        file = null,
                        durationMs = c.getLong(2),
                        sizeBytes = c.getLong(3),
                        isNew = false,
                        cc = Captions.file(ctx, c.getString(1)).exists(),
                        title = MetaStore.loadPlain(ctx, c.getString(1))?.title.orEmpty(),
                    )
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "shelf query", e)
        }
        return out
    }

    /** Copies deck tapes to the shelf, then removes them from the deck. Returns count moved. */
    fun shelve(ctx: Context, tapes: Collection<Tape>): Int {
        var moved = 0
        for (t in tapes) {
            val f = t.file ?: continue
            if (Player.playingId.value == t.id) Player.stop()
            val ok = synchronized(io) {
                f.inputStream().use { putOnShelf(ctx, f.name, it, t.title) }.also { if (it) f.delete() }
            }
            if (ok) moved++
        }
        forget(ctx, tapes.map { it.id })
        bump()
        Notifs.showNewTapes(ctx, newCount(ctx), null)
        return moved
    }

    /** Writes a tape into Recordings/Dic2Phone. Captions and metadata follow by name. */
    fun putOnShelf(ctx: Context, name: String, data: java.io.InputStream, title: String = ""): Boolean {
        val cr = ctx.contentResolver
        var uri: Uri? = null
        return try {
            val values = ContentValues().apply {
                put(MediaStore.Audio.Media.DISPLAY_NAME, name)
                put(MediaStore.Audio.Media.MIME_TYPE, "audio/mp4")
                put(MediaStore.Audio.Media.RELATIVE_PATH, shelfRelPath)
                put(MediaStore.Audio.Media.TITLE, title.ifBlank { "Dic2Phone ${TapeNames.pretty(name)}" })
                put(MediaStore.Audio.Media.IS_PENDING, 1)
            }
            uri = cr.insert(audioCollection, values) ?: return false
            cr.openOutputStream(uri)!!.use { out -> data.copyTo(out) }
            values.clear()
            values.put(MediaStore.Audio.Media.IS_PENDING, 0)
            cr.update(uri, values, null, null)
            true
        } catch (e: Exception) {
            Log.e(TAG, "shelve $name", e)
            uri?.let { u -> runCatching { cr.delete(u, null, null) } }
            false
        }
    }

    // ---- Sharing ----------------------------------------------------------------------------

    /** @param copies tape-effect copies to send instead of the originals (LO-FI send). */
    fun shareIntent(ctx: Context, tapes: List<Tape>, copies: List<File>? = null): Intent? {
        if (tapes.isEmpty()) return null
        val auth = "${ctx.packageName}.files"
        val uris = ArrayList(
            copies?.map { FileProvider.getUriForFile(ctx, auth, it) }
                ?: tapes.map { t -> t.file?.let { FileProvider.getUriForFile(ctx, auth, it) } ?: t.uri }
        )
        if (uris.isEmpty()) return null
        val send = if (uris.size == 1)
            Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris[0])
        else
            Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
        send.type = "audio/mp4"
        send.putExtra(
            Intent.EXTRA_SUBJECT,
            if (tapes.size == 1) tapes[0].title.ifBlank { L.s(R.string.tape_name, TapeNames.pretty(tapes[0].id)) }
            else L.p(R.plurals.share_n, tapes.size)
        )
        send.clipData = ClipData.newRawUri("", uris[0]).apply {
            uris.drop(1).forEach { addItem(ClipData.Item(it)) }
        }
        send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        markHeard(ctx, tapes.filter { it.file != null }.map { it.id })
        return Intent.createChooser(send, L.s(R.string.share_chooser))
    }
}

/**
 * The single tape player. Quick listening from the lists plays a tape straight away; the
 * deck can also hold a [loaded] tape that keeps its place ([deckPos]) between play and pause,
 * and gets scrubbed, wound and flag-jumped.
 */
object Player {
    private val _playingId = MutableStateFlow<String?>(null)
    val playingId: StateFlow<String?> = _playingId
    private val _progress = MutableStateFlow(0f)
    val progress: StateFlow<Float> = _progress
    /** Playback position in ms (for live captions). */
    private val _positionMs = MutableStateFlow(0L)
    val positionMs: StateFlow<Long> = _positionMs
    /** The tape playing comes from the vault (stopped when the vault locks). */
    var playingVault = false
        private set

    /** The tape in the deck, if any. */
    private val _loaded = MutableStateFlow<Tape?>(null)
    val loaded: StateFlow<Tape?> = _loaded
    /** Where the deck tape is (kept while paused). */
    private val _deckPos = MutableStateFlow(0L)
    val deckPos: StateFlow<Long> = _deckPos

    private var mp: MediaPlayer? = null
    private var job: Job? = null
    /** Silences on the tape playing (found in the background when SKIP SILENCE is on). */
    @Volatile private var gaps: Silence.Gaps? = null
    private var gapJob: Job? = null
    private var startAt = 0L
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val h = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            val p = mp ?: return
            var ended = false
            runCatching {
                var pos = p.currentPosition.toLong()
                if (Prefs.skipSilence.value && p.isPlaying) gaps?.jump(pos)?.let { to ->
                    p.seekTo(to.toInt()); pos = to
                }
                _positionMs.value = pos
                if (p.duration > 0) _progress.value = pos.toFloat() / p.duration
                if (_loaded.value?.id == _playingId.value) _deckPos.value = pos
                // Fallback: if the completion callback goes missing, a player that stopped at the end is done.
                ended = !p.isPlaying && p.duration > 0 && pos >= p.duration - 250
            }
            if (ended) { Log.i("Player", "ended (tick)"); completed(); return }
            h.postDelayed(this, 100)
        }
    }

    val deckPlaying: Boolean get() = _loaded.value?.let { it.id == _playingId.value } == true

    fun toggle(ctx: Context, t: Tape) {
        if (_playingId.value == t.id) { stop(); return }
        playFrom(ctx, t, 0L)
    }

    /** Play [t] from [ms]; if it's already playing, just jump there. */
    fun playFrom(ctx: Context, t: Tape, ms: Long) {
        if (_playingId.value == t.id && mp != null) {
            runCatching { mp?.seekTo(ms.toInt()) }
            _positionMs.value = ms
            if (_loaded.value?.id == t.id) _deckPos.value = ms
            return
        }
        stop()
        val app = ctx.applicationContext
        _playingId.value = t.id
        _progress.value = 0f
        _positionMs.value = ms
        if (_loaded.value?.id == t.id) _deckPos.value = ms
        startAt = ms
        playingVault = t.vault != null
        if (t.isNew) TapeStore.markHeard(app, listOf(t.id))
        val fx = Prefs.fx.value
        if (t.vault == null && Prefs.fxPlay.value && fx.any) {
            // Play the tape-effect copy. (Never for vault tapes: the copy would be plaintext on disk.)
            val ready = LoFi.ready(app, t, fx)
            if (ready != null) { LoFi.touch(ready); start(app, t, Uri.fromFile(ready)) }
            else {
                // Not rendered yet (a long tape takes a while): play it clean straight away and
                // slip the effects in, at the same spot, once they're ready.
                start(app, t, t.uri)
                val render = LoFi.warm(app, t, fx)
                job = scope.launch {
                    val f = render.await() ?: return@launch
                    LoFi.touch(f)
                    if (_playingId.value == t.id) swapTo(app, t, Uri.fromFile(f))
                }
            }
        } else start(app, t, t.uri)
    }

    /** Carries on playing [t] from [uri] (its effects copy) where the current player is. */
    private fun swapTo(ctx: Context, t: Tape, uri: Uri) {
        val old = mp ?: return
        if (!runCatching { old.isPlaying }.getOrDefault(false)) return
        try {
            val n = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                setDataSource(ctx, uri)
                setOnCompletionListener { Log.i("Player", "ended (callback)"); completed() }
                prepare()
            }
            if (mp !== old || _playingId.value != t.id) { n.release(); return }
            n.seekTo(old.currentPosition)
            n.start()
            runCatching { n.playbackParams = params() }.onFailure { Log.w("Player", "speed", it) }
            mp = n
            runCatching { old.stop() }; old.release()
            Log.i("Player", "effects in for ${t.id}")
        } catch (e: Exception) {
            Log.w("Player", "effects swap ${t.id}", e)   // keeps playing clean
        }
    }

    private fun start(ctx: Context, t: Tape, uri: Uri) {
        lastStarted = t
        try {
            mp = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                if (t.vault != null) setDataSource(Vault.source(ctx, t) ?: error("vault is locked"))
                else setDataSource(ctx, uri)
                setOnCompletionListener { Log.i("Player", "ended (callback)"); completed() }
                prepare()
                if (startAt > 0) seekTo(startAt.toInt())
                start()
                runCatching { playbackParams = params() }.onFailure { Log.w("Player", "speed", it) }
            }
            h.post(tick)
            findGaps(ctx, t)
        } catch (e: Exception) {
            Log.e("Player", "play ${t.id}", e)
            stop()
        }
    }

    private fun params(): PlaybackParams {
        if (cueFf) return PlaybackParams().setSpeed(CUE_SPEED).setPitch(CUE_PITCH)
        val s = Prefs.speed.value.coerceIn(0.5f, 2f)
        return PlaybackParams().setSpeed(s).setPitch(if (Prefs.tapePitch.value) s else 1f)
    }

    /** New speed / pitch setting: applies to what's playing now. */
    fun applySpeed() {
        val p = mp ?: return
        runCatching { if (p.isPlaying) p.playbackParams = params() }.onFailure { Log.w("Player", "speed", it) }
    }

    /** Finds the tape's silences if SKIP SILENCE is on (or is turned on while it plays). */
    fun findGaps(ctx: Context, t: Tape) {
        val app = ctx.applicationContext
        gaps = Silence.cached(t)
        if (gaps != null || !Prefs.skipSilence.value || gapJob?.isActive == true) return
        gapJob = scope.launch {
            val g = withContext(Dispatchers.IO) { Silence.find(app, t) { _playingId.value != t.id } }
            if (_playingId.value == t.id) gaps = g
        }
    }

    /** Called when SKIP SILENCE is switched on. */
    fun skipSilenceChanged(ctx: Context) {
        val id = _playingId.value ?: return
        val t = _loaded.value?.takeIf { it.id == id } ?: lastStarted?.takeIf { it.id == id } ?: return
        findGaps(ctx, t)
    }
    private var lastStarted: Tape? = null

    /** Played to the end: a deck tape rewinds, ready to play again. */
    private fun completed() {
        if (mp == null) return
        val deck = _loaded.value?.id == _playingId.value
        stop()
        if (deck) _deckPos.value = 0L
    }

    fun stop() {
        job?.cancel()
        job = null
        gapJob?.cancel()
        gapJob = null
        gaps = null
        h.removeCallbacks(tick)
        mp?.let {
            if (_loaded.value?.id == _playingId.value) runCatching { _deckPos.value = it.currentPosition.toLong() }
            runCatching { it.stop() }; it.release()
        }
        mp = null
        playingVault = false
        _playingId.value = null
        _progress.value = 0f
        _positionMs.value = 0L
    }

    // ---- The deck ---------------------------------------------------------------------------

    /** Puts [t] in the deck (from the start), taking out whatever was there. */
    fun load(t: Tape) {
        if (_loaded.value?.id == t.id) { _loaded.value = t; return }
        if (_playingId.value != null) stop()
        _loaded.value = t
        _deckPos.value = 0L
        Prefs.deckTape = if (t.vault == null) t.id else ""
    }

    /** The same tape, re-read (new title, flags...); or null if it's gone, which ejects it. */
    fun refresh(t: Tape?) {
        val cur = _loaded.value ?: return
        if (t == null) eject() else if (t.id == cur.id) _loaded.value = t
    }

    fun eject() {
        if (deckPlaying) stop()
        _loaded.value = null
        _deckPos.value = 0L
        Prefs.deckTape = ""
    }

    fun playPause(ctx: Context) {
        val t = _loaded.value ?: return
        if (deckPlaying) stop()
        else {
            val pos = _deckPos.value.takeIf { t.durationMs <= 0 || it < t.durationMs - 300 } ?: 0L
            playFrom(ctx, t, pos)
        }
    }

    fun seek(ctx: Context, ms: Long) {
        val t = _loaded.value ?: return
        val to = ms.coerceIn(0L, (t.durationMs - 200).coerceAtLeast(0L))
        if (deckPlaying) playFrom(ctx, t, to) else _deckPos.value = to
    }

    fun skip(ctx: Context, deltaMs: Long) = seek(ctx, _deckPos.value + deltaMs)

    // ---- TAPE WIND: holding REW / FF ----------------------------------------------------------

    /** -1 rewinding, 1 fast-forwarding, 0 not winding. */
    private val _winding = MutableStateFlow(0)
    val winding: StateFlow<Int> = _winding
    private var windJob: Job? = null
    /** The deck was playing when the wind started: it plays on from wherever the wind stops. */
    private var windResume = false
    private var windCued = false
    /** CUE fast-forward: the player runs at [CUE_SPEED] instead of the set speed. */
    private var cueFf = false

    /** REW ([dir] -1) or FF (1) held down. With CUE lit the tape is heard as it winds. */
    fun windStart(ctx: Context, dir: Int) {
        val t = _loaded.value ?: return
        if (_winding.value != 0) return
        val app = ctx.applicationContext
        _winding.value = dir
        windResume = deckPlaying
        windCued = Prefs.windCue.value
        windJob = scope.launch { if (windCued) cue(app, t, dir) else spin(t, dir) }
    }

    /** Silent wind: playback stops and the counter runs, ever faster, to the motor's whirr. */
    private suspend fun spin(t: Tape, dir: Int) {
        if (deckPlaying) stop()
        val end = (t.durationMs - 200).coerceAtLeast(0L)
        Feedback.windStart()
        try {
            val t0 = SystemClock.uptimeMillis()
            var last = t0
            while (_loaded.value?.id == t.id) {
                delay(30)
                val now = SystemClock.uptimeMillis()
                val ramp = ((now - t0).toFloat() / WIND_RAMP_MS).coerceIn(0f, 1f)
                val rate = WIND_MIN + (WIND_MAX - WIND_MIN) * ramp * ramp
                Feedback.windSpeed(ramp)
                val to = (_deckPos.value + (dir * rate * (now - last)).toLong()).coerceIn(0L, end)
                last = now
                _deckPos.value = to
                // The tape runs out: the deck clunks to a stop.
                if (to == 0L || to == end) { Feedback.windEnd(); break }
            }
        } finally {
            Feedback.windStop()
        }
    }

    /**
     * CUE: FF plays the tape fast and high; REW plays it *backwards*, just as fast and high,
     * like a real deck reviewing. (MediaPlayer can't run backwards: REW decodes the tape a
     * chunk at a time going back, reverses each chunk and plays it through an AudioTrack.)
     */
    private suspend fun cue(ctx: Context, t: Tape, dir: Int) {
        if (dir > 0) {
            cueFf = true
            if (deckPlaying) applySpeed() else playFrom(ctx, t, _deckPos.value)
            return   // plays fast until let go (or the tape ends)
        }
        if (deckPlaying) stop()   // keeps the deck's place in _deckPos
        val fx = Prefs.fx.value
        // Heard through the effects too, if that's how it plays (and the copy is ready).
        val copy = if (t.vault == null && Prefs.fxPlay.value && fx.any) LoFi.ready(ctx, t, fx) else null
        withContext(Dispatchers.IO) {
            runCatching { reverse(ctx, t, copy, _deckPos.value) }
                .onFailure { if (it !is kotlinx.coroutines.CancellationException) Log.w("Player", "reverse cue", it) }
        }
    }

    /** Plays [t] (or its effects [copy]) backwards from [fromMs] until cancelled or at the start. */
    private suspend fun reverse(ctx: Context, t: Tape, copy: java.io.File?, fromMs: Long) {
        val ex = MediaExtractor()
        var dec: MediaCodec? = null
        var track: AudioTrack? = null
        try {
            when {
                copy != null -> ex.setDataSource(copy.path)
                t.vault != null -> ex.setDataSource(Vault.source(ctx, t) ?: return)
                else -> ex.setDataSource(ctx, t.uri, null)
            }
            val ti = (0 until ex.trackCount).firstOrNull {
                ex.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: return
            ex.selectTrack(ti)
            val fmt = ex.getTrackFormat(ti)
            val sr = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val d = MediaCodec.createDecoderByType(fmt.getString(MediaFormat.KEY_MIME)!!)
            dec = d
            d.configure(fmt, null, null, 0); d.start()
            val minBuf = AudioTrack.getMinBufferSize(
                sr, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT
            )
            val tr = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
                )
                .setAudioFormat(
                    AudioFormat.Builder().setSampleRate(sr)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build()
                )
                .setBufferSizeInBytes(maxOf(minBuf, sr / 5 * 2))   // ~0.2 s of tape: lets go promptly
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
            track = tr
            // AudioTrack won't stretch 4×. Halving the samples gives 2× speed *and* pitch (like
            // tape run fast); the track then doubles the speed again at the same pitch: 4× / 2×,
            // as FF sounds. If the track can't, it's just the tape-like 2×.
            runCatching { tr.playbackParams = PlaybackParams().setSpeed(CUE_SPEED / CUE_PITCH).setPitch(1f) }
                .onFailure { Log.i("Player", "reverse cue: track can't stretch ($it)") }
            tr.play()
            val step = CUE_PITCH.toInt()   // tape samples per sample played

            var endUs = fromMs * 1000
            while (endUs > 0) {
                coroutineContext.ensureActive()
                val startUs = (endUs - REV_CHUNK_US).coerceAtLeast(0L)
                val pcm = decodeRange(ex, d, sr, startUs, endUs)
                pcm.reverse()
                val half = ShortArray(pcm.size / step) { i ->
                    var s = 0
                    for (j in 0 until step) s += pcm[i * step + j]
                    (s / step).toShort()
                }
                // Out in small slices, moving the counter back as it goes.
                var off = 0
                while (off < half.size) {
                    coroutineContext.ensureActive()
                    val n = minOf(REV_SLICE, half.size - off)
                    tr.write(half, off, n)
                    off += n
                    _deckPos.value = ((endUs - off.toLong() * step * 1_000_000L / sr) / 1000).coerceAtLeast(0L)
                }
                endUs = startUs
            }
            _deckPos.value = 0L
            Feedback.windEnd()   // ran back to the start
        } finally {
            track?.let { runCatching { it.pause(); it.flush(); it.stop() }; it.release() }
            dec?.let { runCatching { it.stop() }; it.release() }
            ex.release()
        }
    }

    /** Mono 16-bit samples of the tape from [startUs] to [endUs] (sample-accurate). */
    private fun decodeRange(
        ex: MediaExtractor, d: MediaCodec, sr: Int, startUs: Long, endUs: Long,
    ): ShortArray {
        val out = ShortArray(((endUs - startUs) * sr / 1_000_000L).toInt().coerceAtLeast(0))
        // A frame early, so the decoder is warmed up by the time the wanted audio starts.
        ex.seekTo((startUs - 50_000).coerceAtLeast(0), MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        d.flush()
        val info = MediaCodec.BufferInfo()
        var inDone = false
        var ch = 1
        var floatPcm = false
        while (true) {
            if (!inDone) {
                val i = d.dequeueInputBuffer(5_000)
                if (i >= 0) {
                    val n = ex.readSampleData(d.getInputBuffer(i)!!, 0)
                    if (n < 0 || ex.sampleTime > endUs) {
                        d.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); inDone = true
                    } else { d.queueInputBuffer(i, 0, n, ex.sampleTime, 0); ex.advance() }
                }
            }
            val o = d.dequeueOutputBuffer(info, 5_000)
            if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                val f = d.outputFormat
                ch = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT).coerceAtLeast(1)
                floatPcm = f.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                    f.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
            }
            if (o < 0) continue
            val buf = d.getOutputBuffer(o)!!.order(java.nio.ByteOrder.nativeOrder())
            buf.position(info.offset); buf.limit(info.offset + info.size)
            val frames = info.size / (if (floatPcm) 4 else 2) / ch
            for (k in 0 until frames) {
                val idx = ((info.presentationTimeUs - startUs) * sr / 1_000_000L + k).toInt()
                if (idx < 0) continue
                if (idx >= out.size) break
                var s = 0f
                for (c in 0 until ch) {
                    val p = info.offset + (k * ch + c) * (if (floatPcm) 4 else 2)
                    s += if (floatPcm) buf.getFloat(p) * 32767f else buf.getShort(p).toFloat()
                }
                out[idx] = (s / ch).toInt().coerceIn(-32768, 32767).toShort()
            }
            val eos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
            d.releaseOutputBuffer(o, false)
            if (eos) break
        }
        return out
    }

    /** REW / FF let go. */
    fun windStop(ctx: Context) {
        if (_winding.value == 0) return
        _winding.value = 0
        windJob?.cancel()
        windJob = null
        Feedback.windStop()
        val wasCueFf = cueFf
        cueFf = false
        val t = _loaded.value ?: return
        when {
            // CUE REW ran on its own track (the player is stopped): play on from where it got to.
            // CUE FF: it is playing already (unless it ran off the end): back to normal, or stop.
            windCued && !wasCueFf -> if (windResume && _deckPos.value < t.durationMs - 300) playFrom(ctx, t, _deckPos.value)
            windCued -> if (deckPlaying) { if (windResume) applySpeed() else stop() }
            windResume && _deckPos.value < t.durationMs - 300 -> playFrom(ctx, t, _deckPos.value)
        }
    }

    /** Wind speed in tape time per real time: starts slow, the motor spins up over [WIND_RAMP_MS]. */
    private const val WIND_MIN = 6f
    private const val WIND_MAX = 30f
    private const val WIND_RAMP_MS = 3000f
    private const val CUE_SPEED = 4f
    private const val CUE_PITCH = 2f
    /** CUE REW decodes this much tape at a time (then plays it reversed). */
    private const val REV_CHUNK_US = 1_000_000L
    private const val REV_SLICE = 1024
}
