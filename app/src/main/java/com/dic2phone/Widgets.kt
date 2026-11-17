package com.dic2phone

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.widget.RemoteViews
import androidx.compose.ui.graphics.toArgb
import com.dic2phone.ui.DeckArt
import com.dic2phone.ui.Palette
import com.dic2phone.ui.Themes

abstract class DeckWidget : AppWidgetProvider() {
    override fun onUpdate(ctx: Context, m: AppWidgetManager, ids: IntArray) = Widgets.updateAll(ctx)
}

class CounterWidget : DeckWidget()
class RecWidget : DeckWidget()
class ComboWidget : DeckWidget()

/** Home/lock-screen widgets. Drawn with [DeckArt] bitmaps so they follow the selected theme. */
object Widgets {
    val kinds = listOf(CounterWidget::class.java, RecWidget::class.java, ComboWidget::class.java)

    fun updateAll(ctx: Context) {
        val m = AppWidgetManager.getInstance(ctx)
        val p = Themes.byId(Prefs.theme.value)
        val rec = Recorder.state.value
        val count by lazy { TapeStore.newCount(ctx) }
        for (cls in kinds) {
            val ids = m.getAppWidgetIds(ComponentName(ctx, cls))
            if (ids.isEmpty()) continue
            val v = when (cls) {
                CounterWidget::class.java -> RemoteViews(ctx.packageName, R.layout.widget_counter).also {
                    bindCounter(it, p, count)
                    it.setImageViewBitmap(R.id.bg, panel(p, 400, 170))
                    it.setOnClickPendingIntent(R.id.root, openMain(ctx))
                }
                RecWidget::class.java -> RemoteViews(ctx.packageName, R.layout.widget_rec).also {
                    bindRec(it, p, rec)
                    it.setImageViewBitmap(R.id.bg, panel(p, 400, 170))
                    it.setOnClickPendingIntent(R.id.root, quickRec(ctx))
                }
                else -> RemoteViews(ctx.packageName, R.layout.widget_combo).also {
                    bindCounter(it, p, count)
                    bindRec(it, p, rec)
                    it.setImageViewBitmap(R.id.bg, panel(p, 600, 170))
                    it.setOnClickPendingIntent(R.id.left, openMain(ctx))
                    it.setOnClickPendingIntent(R.id.right, quickRec(ctx))
                }
            }
            m.updateAppWidget(ids, v)
        }
    }

    /** Ask the launcher to add a widget (Android shows its own confirmation). */
    fun pin(ctx: Context, cls: Class<*>): Boolean {
        val m = AppWidgetManager.getInstance(ctx)
        if (!m.isRequestPinAppWidgetSupported) return false
        return m.requestPinAppWidget(ComponentName(ctx, cls), null, null)
    }

    private fun bindCounter(v: RemoteViews, p: Palette, count: Int) {
        v.setImageViewBitmap(R.id.counter, counter(p, count))
        v.setTextColor(R.id.label, p.dim.toArgb())
        v.setContentDescription(R.id.counter, L.p(R.plurals.w_new_tapes, count))
    }

    private fun bindRec(v: RemoteViews, p: Palette, rec: Recorder.State) {
        v.setImageViewBitmap(R.id.led, led(p, rec.recording))
        v.setTextViewText(R.id.rec_label, L.s(if (rec.recording) R.string.deck_rec else R.string.w_standby))
        v.setTextColor(R.id.rec_label, (if (rec.recording) p.led else p.dim).toArgb())
        v.setTextColor(R.id.chrono, p.led.toArgb())
        v.setTextColor(R.id.idle, p.text.toArgb())
        if (rec.recording) {
            v.setChronometer(R.id.chrono, rec.startedAt, null, true)
            v.setViewVisibility(R.id.chrono, View.VISIBLE)
            v.setViewVisibility(R.id.idle, View.GONE)
        } else {
            v.setChronometer(R.id.chrono, 0L, null, false)
            v.setViewVisibility(R.id.chrono, View.GONE)
            v.setViewVisibility(R.id.idle, View.VISIBLE)
        }
    }

    private fun panel(p: Palette, w: Int, h: Int) =
        Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).also { DeckArt.panel(Canvas(it), w.toFloat(), h.toFloat(), p) }

    private fun counter(p: Palette, value: Int): Bitmap {
        val dh = 90f
        val w = (dh * .2f + 3 * dh * .72f + 2 * dh * .08f).toInt() + 2
        val bmp = Bitmap.createBitmap(w, (dh * 1.2f).toInt() + 2, Bitmap.Config.ARGB_8888)
        DeckArt.counter(Canvas(bmp), value, dh, p)
        return bmp
    }

    private fun led(p: Palette, on: Boolean) =
        Bitmap.createBitmap(72, 72, Bitmap.Config.ARGB_8888).also { DeckArt.led(Canvas(it), 36f, 36f, 15f, on, p) }

    private fun openMain(ctx: Context) = PendingIntent.getActivity(
        ctx, 10, Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    )

    private fun quickRec(ctx: Context) = PendingIntent.getActivity(
        ctx, 11, Intent(ctx, QuickRecordActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    )
}
