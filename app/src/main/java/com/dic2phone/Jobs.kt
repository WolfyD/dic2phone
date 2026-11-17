package com.dic2phone

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Captions for new tapes without asking: right after recording, or held back until the phone
 * has been left alone for a while (Android's "device idle": screen off and unused, usually
 * overnight). Needs a downloaded speech model; does nothing otherwise.
 */
object AutoCaptions {
    private const val TAG = "AutoCaptions"
    private const val KEY = "auto_cc_pending"
    const val JOB_ID = 42

    private fun sp(ctx: Context) = ctx.getSharedPreferences("tapes", Context.MODE_PRIVATE)

    /** The speech model to use, if it's downloaded. */
    fun model(ctx: Context): Transcriber.Model? =
        Transcriber.Model.byId(Prefs.ccModel.value)?.takeIf { Transcriber.installed(ctx, it) }

    /** New tapes from a recording session. */
    fun recorded(ctx: Context, tapes: List<Tape>) {
        if (tapes.isEmpty() || !Whisper.available) return
        when (Prefs.autoCc.value) {
            Prefs.AUTO_CC_NOW -> if (model(ctx) != null) Transcriber.enqueue(ctx, tapes)
            Prefs.AUTO_CC_IDLE -> {
                val p = sp(ctx)
                p.edit().putStringSet(KEY, HashSet(p.getStringSet(KEY, emptySet())!!) + tapes.map { it.id }).apply()
                sync(ctx)
            }
        }
    }

    /** Tapes waiting for the phone to go idle. */
    fun pending(ctx: Context): Set<String> = sp(ctx).getStringSet(KEY, emptySet())!!

    /** Schedules (or cancels) the idle job to match the setting and what's waiting. */
    fun sync(ctx: Context) {
        val js = ctx.getSystemService(JobScheduler::class.java)
        if (Prefs.autoCc.value != Prefs.AUTO_CC_IDLE || pending(ctx).isEmpty()) { js.cancel(JOB_ID); return }
        if (js.getPendingJob(JOB_ID) != null) return
        js.schedule(
            JobInfo.Builder(JOB_ID, ComponentName(ctx, Jobs::class.java))
                .setRequiresDeviceIdle(true)
                .setRequiresBatteryNotLow(true)
                .setPersisted(true)
                .build()
        )
        Log.i(TAG, "waiting for idle: ${pending(ctx).size} tapes")
    }

    /** The phone is idle: caption what's waiting. @return false if it has to try again later. */
    fun runIdle(ctx: Context): Boolean {
        val ids = pending(ctx)
        if (ids.isEmpty() || Prefs.autoCc.value != Prefs.AUTO_CC_IDLE) return true
        if (model(ctx) == null) return true   // no model: nothing to do (kept until there is one)
        val tapes = TapeStore.deck(ctx).filter { it.id in ids && !it.cc } +
            TapeStore.shelf(ctx).filter { it.id in ids && !it.cc }
        if (tapes.isNotEmpty() && !Transcriber.enqueue(ctx, tapes)) return false
        Log.i(TAG, "idle: captioning ${tapes.size} tapes")
        sp(ctx).edit().putStringSet(KEY, HashSet(pending(ctx)) - ids).apply()
        return true
    }
}

/**
 * Auto-tidy: heard deck tapes older than the chosen number of days are deleted. Tapes with
 * a title or flags, unheard ones, the one in the deck, and everything on the shelf or in the
 * vault are kept. Tapes due within [WARN_DAYS] are shown on the deck and marked in the list.
 */
object Tidy {
    private const val TAG = "Tidy"
    const val JOB_ID = 41
    const val WARN_DAYS = 3

    /** Deck tapes auto-tidy will delete, with when (wall-clock ms). */
    fun due(ctx: Context, deck: List<Tape> = TapeStore.deck(ctx)): Map<String, Long> {
        val days = Prefs.tidyDays.value
        if (days <= 0) return emptyMap()
        val day = Prefs.tidyDayMs
        val keep = setOfNotNull(Player.loaded.value?.id, Prefs.deckTape.ifEmpty { null }, Player.playingId.value)
        return deck.filter { it.file != null && it.vault == null && !it.isNew && it.title.isBlank() && it.id !in keep }
            .mapNotNull { t ->
                val m = MetaStore.loadPlain(ctx, t.id)
                if (m != null && (m.flags.isNotEmpty() || m.title.isNotBlank())) return@mapNotNull null
                val at = m?.endedAt?.takeIf { it > 0 } ?: t.file!!.lastModified()
                t.id to at + days * day
            }.toMap()
    }

    /** Due within the warning window (includes overdue). */
    fun soon(ctx: Context, deck: List<Tape> = TapeStore.deck(ctx)): Map<String, Long> {
        val limit = System.currentTimeMillis() + WARN_DAYS * Prefs.tidyDayMs
        return due(ctx, deck).filterValues { it <= limit }
    }

    fun run(ctx: Context) {
        if (Prefs.tidyDays.value <= 0 || Recorder.state.value.recording) return
        val now = System.currentTimeMillis()
        val deck = TapeStore.deck(ctx)
        val gone = due(ctx, deck).filterValues { it <= now }.keys
        if (gone.isEmpty()) return
        val failed = TapeStore.delete(ctx, deck.filter { it.id in gone })
        Log.i(TAG, "tidied ${gone.size - failed} tapes: $gone")
    }

    fun schedule(ctx: Context) {
        val js = ctx.getSystemService(JobScheduler::class.java)
        if (Prefs.tidyDays.value <= 0) { js.cancel(JOB_ID); return }
        if (js.getPendingJob(JOB_ID) != null) return
        js.schedule(
            JobInfo.Builder(JOB_ID, ComponentName(ctx, Jobs::class.java))
                .setPeriodic(6 * 3600_000L)
                .setPersisted(true)
                .build()
        )
    }

    /** Human "in 2 days" / "today" for a due time. */
    fun whenText(at: Long): String {
        val left = at - System.currentTimeMillis()
        val d = (left / Prefs.tidyDayMs).toInt()
        return when {
            left <= 0 -> L.s(R.string.when_soon)
            d == 0 -> L.s(R.string.when_today)
            d == 1 -> L.s(R.string.when_tomorrow)
            else -> L.p(R.plurals.when_days, d)
        }
    }
}

/**
 * PLAY WITH EFFECTS: makes the effects copies tapes don't have yet while the phone is left
 * alone (Android's "device idle"), so they play with effects straight away. Not on battery
 * saver or low battery, not while recording; one tape at a time, stopping when the phone is
 * picked up. Also clears out copies whose tape is gone.
 */
object FxPrep {
    private const val TAG = "FxPrep"
    const val JOB_ID = 43
    @Volatile var stopped = false

    fun sync(ctx: Context) {
        val js = ctx.getSystemService(JobScheduler::class.java)
        if (!Prefs.fxPlay.value || !Prefs.fx.value.any) { js.cancel(JOB_ID); return }
        if (js.getPendingJob(JOB_ID) != null) return
        js.schedule(
            JobInfo.Builder(JOB_ID, ComponentName(ctx, Jobs::class.java))
                .setRequiresDeviceIdle(true)
                .setRequiresBatteryNotLow(true)
                .setPersisted(true)
                .build()
        )
    }

    /** Copies whose tape is gone (and unplayed ones, if set) are deleted. */
    fun tidy(ctx: Context) {
        val tapes = TapeStore.deck(ctx) + TapeStore.shelf(ctx)
        LoFi.tidy(ctx, tapes.map { it.id }.toSet())
    }

    /** @return false if it has to carry on another time. */
    suspend fun runIdle(ctx: Context): Boolean {
        stopped = false
        val tapes = TapeStore.deck(ctx) + TapeStore.shelf(ctx)
        LoFi.tidy(ctx, tapes.map { it.id }.toSet())
        val fx = Prefs.fx.value
        if (!Prefs.fxPlay.value || !fx.any) return true
        val pm = ctx.getSystemService(android.os.PowerManager::class.java)
        val todo = tapes.filter { it.vault == null && LoFi.ready(ctx, it, fx) == null }
        if (todo.isNotEmpty()) Log.i(TAG, "idle: ${todo.size} tapes to render")
        for (t in todo) {
            if (stopped || pm.isPowerSaveMode || Recorder.state.value.recording) return false
            LoFi.warm(ctx, t, fx).await()
        }
        return true
    }
}

/** Runs [Tidy] (periodic), and [AutoCaptions] and [FxPrep] (when the phone is idle). */
class Jobs : JobService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onStartJob(params: JobParameters): Boolean {
        scope.launch {
            var retry = false
            runCatching {
                when (params.jobId) {
                    Tidy.JOB_ID -> Tidy.run(applicationContext)
                    AutoCaptions.JOB_ID -> retry = !AutoCaptions.runIdle(applicationContext)
                    FxPrep.JOB_ID -> retry = !FxPrep.runIdle(applicationContext)
                }
            }.onFailure { Log.w("Jobs", "job ${params.jobId}", it) }
            jobFinished(params, retry)
        }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        if (params.jobId == FxPrep.JOB_ID) { FxPrep.stopped = true; return true }
        return params.jobId == AutoCaptions.JOB_ID
    }
}
