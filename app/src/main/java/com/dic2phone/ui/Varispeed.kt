package com.dic2phone.ui

import com.dic2phone.R
import com.dic2phone.L
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.dic2phone.Feedback
import com.dic2phone.Prefs
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.coroutines.launch

/** How far the knob follows the finger away from a notch before it gives and drops into the next. */
private const val DETENT_GIVE = 0.3f

/**
 * The deck's varispeed: a short fader with a notch per speed in [Prefs.SPEEDS]. It's notched like
 * a real one: the knob sticks in a notch, lags behind the finger, then clunks into the next
 * notch with a tick (sound + haptic), and springs home when let go. Changes apply at once,
 * also while the tape plays. Tap anywhere on it to go straight to the nearest notch.
 */
@Composable
fun VarispeedFader(modifier: Modifier = Modifier) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val speed by Prefs.speed.collectAsStateWithLifecycle()
    val stops = Prefs.SPEEDS
    val last = stops.size - 1
    fun indexOf(s: Float) = stops.indices.minBy { abs(stops[it].first - s) }
    val cur = indexOf(speed)

    val knob = remember { Animatable(cur.toFloat()) }
    var dragging by remember { mutableStateOf(false) }
    var raw by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(cur) {
        if (!dragging) knob.animateTo(cur.toFloat(), spring(dampingRatio = .45f, stiffness = 900f))
    }
    fun select(i: Int) {
        if (i != indexOf(Prefs.speed.value)) { Prefs.setSpeed(stops[i].first); Feedback.detent(ctx) }
    }

    val measurer = rememberTextMeasurer()
    val p = Deck.palette
    val label = stops[cur].second + "×"
    Canvas(
        modifier
            .fillMaxWidth()
            .height(44.dp)
            .semantics { contentDescription = L.s(R.string.a11y_speed, label) }
            .pointerInput(stops.size) {
                val inset = 14.dp.toPx()
                val step = (size.width - 2 * inset) / last
                detectTapGestures { o ->
                    val i = ((o.x - inset) / step).roundToInt().coerceIn(0, last)
                    select(i)
                    scope.launch { knob.animateTo(i.toFloat(), spring(dampingRatio = .45f, stiffness = 900f)) }
                }
            }
            .pointerInput(stops.size) {
                val inset = 14.dp.toPx()
                val step = (size.width - 2 * inset) / last
                detectHorizontalDragGestures(
                    onDragStart = { dragging = true; raw = knob.value },
                    onDragEnd = {
                        dragging = false
                        scope.launch { knob.animateTo(raw.roundToInt().toFloat(), spring(dampingRatio = .45f, stiffness = 900f)) }
                    },
                    onDragCancel = {
                        dragging = false
                        scope.launch { knob.animateTo(indexOf(Prefs.speed.value).toFloat(), spring(dampingRatio = .45f, stiffness = 900f)) }
                    },
                ) { change, dx ->
                    change.consume()
                    raw = (raw + dx / step).coerceIn(0f, last.toFloat())
                    val near = raw.roundToInt()
                    select(near)
                    // Sticky: the knob only gives a little away from its notch, then jumps.
                    scope.launch { knob.snapTo(near + (raw - near) * DETENT_GIVE) }
                }
            }
    ) {
        val w = size.width
        val inset = 14.dp.toPx()
        val step = (w - 2 * inset) / last
        val slotY = 15.dp.toPx()
        // The slot the knob runs in.
        val slotH = 6.dp.toPx()
        drawRoundRect(
            Color.Black, Offset(inset - 6.dp.toPx(), slotY - slotH / 2),
            Size(w - 2 * inset + 12.dp.toPx(), slotH), CornerRadius(slotH / 2)
        )
        drawRoundRect(
            Color.White.copy(alpha = .12f), Offset(inset - 6.dp.toPx(), slotY + slotH / 2 - 1.dp.toPx()),
            Size(w - 2 * inset + 12.dp.toPx(), 1.dp.toPx())
        )
        // Notches + their speeds printed under them; 1× gets the longer mark.
        stops.forEachIndexed { i, (_, l) ->
            val x = inset + i * step
            val on = i == cur
            val tick = if (stops[i].first == 1f) 7.dp.toPx() else 4.dp.toPx()
            drawRect(
                if (on) Deck.amber else Deck.dim, Offset(x - 1.dp.toPx(), slotY + 6.dp.toPx()),
                Size(2.dp.toPx(), tick)
            )
            val text = measurer.measure(
                if (i == last) "$l×" else l,
                TextStyle(
                    fontFamily = Mono, fontSize = 11.sp, color = if (on) Deck.amber else Deck.dim,
                    fontWeight = if (on) FontWeight.Bold else FontWeight.Normal
                )
            )
            val tx = (x - text.size.width / 2f).coerceIn(0f, w - text.size.width)
            drawText(text, topLeft = Offset(tx, size.height - text.size.height))
        }
        // The knob: a ridged cap with a line across it, casting a little shadow.
        val kx = inset + knob.value * step
        val kw = 18.dp.toPx(); val kh = 24.dp.toPx()
        val top = slotY - kh / 2
        val r = CornerRadius(3.dp.toPx())
        drawRoundRect(Color.Black.copy(alpha = .45f), Offset(kx - kw / 2 + 1.dp.toPx(), top + 2.dp.toPx()), Size(kw, kh), r)
        drawRoundRect(
            Brush.verticalGradient(listOf(p.key1, p.key2, lerp(p.key2, Color.Black, .35f)), startY = top, endY = top + kh),
            Offset(kx - kw / 2, top), Size(kw, kh), r
        )
        drawRoundRect(Color.Black.copy(alpha = .55f), Offset(kx - kw / 2, top), Size(kw, kh), r, style = Stroke(1.dp.toPx()))
        for (g in listOf(-7, -4, 4, 7)) {
            val y = slotY + g.dp.toPx()
            drawRect(Color.Black.copy(alpha = .28f), Offset(kx - kw / 2 + 3.dp.toPx(), y), Size(kw - 6.dp.toPx(), 1.dp.toPx()))
        }
        drawRect(Deck.amber, Offset(kx - 1.dp.toPx(), top + 3.dp.toPx()), Size(2.dp.toPx(), kh - 6.dp.toPx()))
    }
}
