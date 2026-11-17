package com.dic2phone

import android.graphics.Paint
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.service.wallpaper.WallpaperService
import android.text.TextPaint
import android.view.SurfaceHolder
import androidx.compose.ui.graphics.toArgb
import com.dic2phone.ui.DeckArt
import com.dic2phone.ui.Themes
import com.dic2phone.ui.deckLabel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.min

/**
 * The deck as a live wallpaper. Static redraws on state changes; animates (~30 fps) only while
 * recording or playing and only while visible, so it costs nothing the rest of the time.
 */
class DeckWallpaperService : WallpaperService() {
    override fun onCreateEngine(): Engine = DeckEngine()

    private inner class DeckEngine : Engine() {
        private val h = Handler(Looper.getMainLooper())
        private var scope: CoroutineScope? = null
        private var visible = false
        private var w = 0; private var ht = 0

        private var newCount = 0
        private var last: Tape? = null
        private var angle = 0f
        private var needle = 0f
        private var lastFrame = 0L

        private val frame = object : Runnable {
            override fun run() {
                draw()
                if (visible && animating()) h.postDelayed(this, 33)
            }
        }

        private fun animating() = Recorder.state.value.recording || Player.playingId.value != null

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            setTouchEventsEnabled(false)
            val s = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
            scope = s
            s.launch {
                combine(
                    listOf<Flow<Any?>>(
                        Recorder.state.map { it.recording }.distinctUntilChanged(),
                        Player.playingId, TapeStore.version, Prefs.theme, Prefs.tapeLabel, Prefs.minidisc,
                    )
                ) { }.collect {
                    withContext(Dispatchers.IO) { loadTapes() }
                    kick()
                }
            }
        }

        private fun loadTapes() {
            val ctx = this@DeckWallpaperService
            newCount = TapeStore.newCount(ctx)
            last = runCatching { TapeStore.deck(ctx).firstOrNull() }.getOrNull()
        }

        private fun kick() {
            h.removeCallbacks(frame)
            lastFrame = 0L
            if (visible) h.post(frame)
        }

        override fun onVisibilityChanged(v: Boolean) {
            visible = v
            if (v) kick() else h.removeCallbacks(frame)
        }

        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            super.onSurfaceChanged(holder, format, width, height)
            w = width; ht = height
            kick()
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            visible = false
            h.removeCallbacks(frame)
            super.onSurfaceDestroyed(holder)
        }

        override fun onDestroy() {
            h.removeCallbacks(frame)
            scope?.cancel()
            super.onDestroy()
        }

        private fun draw() {
            if (w == 0 || ht == 0) return
            val rec = Recorder.state.value
            val playing = Player.playingId.value != null
            val now = SystemClock.elapsedRealtime()
            if (rec.tapeMoving || playing) {
                if (lastFrame != 0L) angle = (angle + (now - lastFrame) / 1000f * 220f) % 360f
                lastFrame = now
            } else lastFrame = 0L   // paused (e.g. VOX waiting): pick up again without a jump
            val target = if (rec.recording) rec.level else 0f
            needle = if (rec.recording) needle + (target - needle) * .35f else 0f

            val holder = surfaceHolder
            val c = runCatching { holder.lockCanvas() }.getOrNull() ?: return
            try {
                val p = Themes.byId(Prefs.theme.value)
                val W = w.toFloat(); val H = ht.toFloat()
                DeckArt.background(c, W, H, p)

                val cw = min(W * .86f, H * .5f)
                val left = (W - cw) / 2
                val cassetteH = cw / DeckArt.CASSETTE_RATIO
                val vuW = cw * .7f
                val vuH = vuW / DeckArt.VU_RATIO
                val dh = cw * .11f
                val rowH = dh * 1.2f + cw * .06f
                val gap = cw * .06f
                val brandH = cw * .25f
                val total = brandH + gap + rowH + gap + cassetteH + gap + vuH
                var y = (H - total) / 2

                DeckArt.brand(c, W / 2, y, cw, p, Prefs.minidisc.value)
                y += brandH + gap

                // Counter + label (left), LED + time (right)
                c.save(); c.translate(left, y)
                DeckArt.counter(c, newCount, dh, p)
                c.restore()
                val tp = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                    typeface = DeckArt.monoPlain; textSize = cw * .035f; color = p.dim.toArgb()
                }
                c.drawText(L.s(R.string.deck_new_tapes), left, y + dh * 1.2f + cw * .045f, tp)

                val elapsed = if (rec.recording) now - rec.startedAt else 0L
                val tt = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                    typeface = DeckArt.mono; textSize = cw * .09f
                    color = (if (rec.recording) p.led else p.dim).toArgb(); textAlign = Paint.Align.RIGHT
                }
                c.drawText(TapeNames.duration(elapsed), left + cw, y + dh * 1.1f, tt)
                tp.textAlign = Paint.Align.RIGHT
                c.drawText(L.s(R.string.deck_rec), left + cw - cw * .07f, y + cw * .04f - tp.ascent() / 2, tp)
                DeckArt.led(c, left + cw - cw * .025f, y + cw * .04f, cw * .022f, rec.recording, p)
                y += rowH + gap

                c.save(); c.translate(left, y)
                val disc = Prefs.minidisc.value
                val (label, sub) = deckLabel(Prefs.tapeLabel.value, disc, rec.recording, playing, last)
                DeckArt.media(
                    c, cw, p, label, sub,
                    angle,
                    when {
                        rec.recording -> (elapsed / 600_000f).coerceAtMost(1f)
                        playing -> Player.progress.value
                        else -> 0f
                    },
                    rec.tapeMoving || playing, disc, Prefs.tapeLabel.value.isNotBlank(),
                )
                c.restore()
                y += cassetteH + gap

                c.save(); c.translate((W - vuW) / 2, y)
                DeckArt.vu(c, vuW, p, needle)
                c.restore()
            } finally {
                runCatching { holder.unlockCanvasAndPost(c) }
            }
        }
    }
}
