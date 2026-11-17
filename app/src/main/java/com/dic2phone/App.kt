package com.dic2phone

import android.Manifest
import android.app.Application
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

class App : Application() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onCreate() {
        super.onCreate()
        L.app = this
        Prefs.init(this)
        fun font(id: Int) = runCatching { androidx.core.content.res.ResourcesCompat.getFont(this, id) }.getOrNull()
        font(R.font.reenie_beanie)?.let { com.dic2phone.ui.DeckArt.hand = it }
        font(R.font.courier_prime_regular)?.let { com.dic2phone.ui.DeckArt.monoPlain = it }
        font(R.font.courier_prime_bold)?.let { com.dic2phone.ui.DeckArt.mono = it }
        font(R.font.barlow_bold)?.let { com.dic2phone.ui.DeckArt.sans = it }
        font(R.font.barlow_black_italic)?.let { com.dic2phone.ui.DeckArt.brandFace = it }
        Notifs.createChannels(this)
        // Tapes cut off by a crash or a dead battery: rebuilt from their journals.
        val cutOff = runCatching { Rescue.leftovers(this) }.getOrDefault(emptyList())
        if (cutOff.isNotEmpty()) scope.launch {
            runCatching { Rescue.recover(this@App, cutOff) }.onFailure { Log.w("App", "rescue", it) }
        }
        runCatching { Tidy.schedule(this); AutoCaptions.sync(this); FxPrep.sync(this) }.onFailure { Log.w("App", "jobs", it) }
        scope.launch { runCatching { Tidy.run(this@App) }.onFailure { Log.w("App", "tidy", it) } }
        scope.launch { runCatching { FxPrep.tidy(this@App) }.onFailure { Log.w("App", "fx tidy", it) } }
        // Keep the home-screen widgets in sync with recording state, tape count and theme.
        scope.launch {
            combine(
                Recorder.state.map { it.recording to it.startedAt }.distinctUntilChanged(),
                TapeStore.version,
                Prefs.theme,
            ) { _, _, _ -> }.collect {
                runCatching { Widgets.updateAll(this@App) }.onFailure { Log.w("App", "widget update", it) }
            }
        }
    }
}

object Notifs {
    private const val CH_REC = "recording"
    private const val CH_TAPES = "tapes"
    const val ID_REC = 1
    private const val ID_TAPES = 2

    fun createChannels(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CH_REC, L.s(R.string.ch_rec), NotificationManager.IMPORTANCE_LOW).apply {
                setSound(null, null)
                enableVibration(false)
                description = L.s(R.string.ch_rec_desc)
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(CH_TAPES, L.s(R.string.ch_tapes), NotificationManager.IMPORTANCE_LOW).apply {
                setShowBadge(true)
                description = L.s(R.string.ch_tapes_desc)
            }
        )
    }

    /**
     * @param latched recording stays on by itself (LOCKED), so the notification gets a STOP key.
     * @param vox noise-activated; [rolling] whether there's sound right now.
     */
    fun recording(
        ctx: Context, latched: Boolean = false, vox: Boolean = false, rolling: Boolean = true,
        since: Long = System.currentTimeMillis(), flags: Int = 0, part: Int = 0,
    ): Notification =
        NotificationCompat.Builder(ctx, CH_REC)
            .setSmallIcon(R.drawable.ic_cassette)
            .setContentTitle(
                when {
                    vox && !rolling -> L.s(R.string.n_rec_waiting)
                    latched -> L.s(R.string.n_rec_locked)
                    else -> L.s(R.string.n_rec)
                }
            )
            .setContentText(
                listOfNotNull(
                    if (latched) L.s(R.string.n_rec_latched) else L.s(R.string.n_rec_text),
                    if (vox) L.s(R.string.meta_mode_vox) else null,
                    if (part > 1) L.s(R.string.n_rec_part, part) else null,
                    if (flags > 0) "⚑ $flags" else null,
                ).joinToString(" · ")
            )
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setUsesChronometer(true)
            .setWhen(since)
            .apply {
                if (latched) addAction(
                    0, L.s(R.string.stop),
                    PendingIntent.getService(
                        ctx, 1, android.content.Intent(ctx, RecorderService::class.java).setAction(RecorderService.ACTION_STOP),
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    )
                )
            }
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(openApp(ctx))
            .build()

    fun showNewTapes(ctx: Context, count: Int, last: String?) {
        if (count <= 0) {
            clearNewTapes(ctx); return
        }
        if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) return
        val n = NotificationCompat.Builder(ctx, CH_TAPES)
            .setSmallIcon(R.drawable.ic_cassette)
            .setContentTitle(L.p(R.plurals.n_new_tapes, count))
            .setContentText(last?.let { L.s(R.string.n_latest, TapeNames.pretty(it)) } ?: "")
            .setNumber(count)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setAutoCancel(true)
            .setContentIntent(openApp(ctx))
            .build()
        ctx.getSystemService(NotificationManager::class.java).notify(ID_TAPES, n)
    }

    fun clearNewTapes(ctx: Context) {
        ctx.getSystemService(NotificationManager::class.java).cancel(ID_TAPES)
    }

    private fun openApp(ctx: Context): PendingIntent = PendingIntent.getActivity(
        ctx, 0,
        Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    )
}
