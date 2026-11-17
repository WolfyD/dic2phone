package com.dic2phone.ui

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredHeight
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.dic2phone.Feedback
import com.dic2phone.R
import com.dic2phone.Tape
import com.dic2phone.TapeNames
import kotlinx.coroutines.delay

/** What the disc stack stands in: the deck's black case, the wooden shelf, the steel vault. */
internal enum class DiscFrame { CASE, WOOD, STEEL }

/** Disc shell colours, picked per tape (by name, so a disc keeps its colour whatever the sort). */
private val SHELLS = listOf(
    Color(0xFF26262B), Color(0xFFC62A3C), Color(0xFFE2702A), Color(0xFF3E9E4C),
    Color(0xFF27AEC2), Color(0xFF7A3FB6), Color(0xFF5A6C8A),
)

private fun shellOf(t: Tape) = SHELLS[(t.id.hashCode() and 0x7FFFFFFF) % SHELLS.size]

private val STRIP = 50.dp       // how much of a disc shows above the next one in the stack
private val CHAMFER = 16.dp

/**
 * Disc mode's tape list: MiniDiscs stacked like cards, each one's label edge showing above the
 * next. Tap a disc to pull it out of the stack and read its whole label; tap the pulled-out
 * one to play it (or, choosing what to load, put it in the deck). Long-press selects.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun DiscStack(
    tapes: List<Tape>, selected: Set<String>, playing: String?, progress: Float, queued: Set<String>,
    tidy: Map<String, Long>, inDeck: String?, loadMode: Boolean, frame: DiscFrame, modifier: Modifier,
    onTap: (Tape) -> Unit, onLong: (Tape) -> Unit, onLoad: (Tape) -> Unit,
) {
    val ctx = LocalContext.current
    var lifted by remember { mutableStateOf<String?>(null) }
    val state = rememberLazyListState()
    val density = LocalDensity.current

    // The pulled-out disc is scrolled fully into view once it has slid out.
    LaunchedEffect(lifted) {
        val id = lifted ?: return@LaunchedEffect
        delay(280)
        val info = state.layoutInfo
        val item = info.visibleItemsInfo.firstOrNull { it.key == id } ?: return@LaunchedEffect
        val over = item.offset + item.size - (info.viewportEndOffset - info.afterContentPadding)
        val under = item.offset - info.viewportStartOffset - info.beforeContentPadding
        when {
            under < 0 -> state.animateScrollBy(under.toFloat())
            over > 0 -> state.animateScrollBy(minOf(over, under).toFloat())
        }
    }

    val shape = RoundedCornerShape(8.dp)
    val back = when (frame) {
        DiscFrame.CASE -> Brush.verticalGradient(listOf(Color(0xFF1A1A1C), Color(0xFF0A0A0B)))
        DiscFrame.WOOD -> Brush.verticalGradient(listOf(Color(0xFF2C1C10), Color(0xFF1E1309)))
        DiscFrame.STEEL -> Brush.verticalGradient(listOf(Color(0xFF22262B), Color(0xFF15181B)))
    }
    val rail = when (frame) {
        DiscFrame.CASE -> null
        DiscFrame.WOOD -> Brush.horizontalGradient(listOf(Color(0xFF5A3A22), Color(0xFF7A5232), Color(0xFF5A3A22)))
        DiscFrame.STEEL -> Brush.horizontalGradient(listOf(Color(0xFF5E646B), Color(0xFFB4BAC0), Color(0xFF5E646B)))
    }
    Row(
        modifier.clip(shape).background(back)
            .border(2.dp, if (frame == DiscFrame.CASE) Color(0xFF2C2C30) else Color.Black.copy(alpha = .5f), shape)
    ) {
        rail?.let { Box(Modifier.width(10.dp).fillMaxHeight().background(it)) }
        BoxWithConstraints(Modifier.weight(1f).fillMaxHeight()) {
            val full = (maxWidth * .6f).coerceIn(170.dp, 240.dp)
            LazyColumn(
                Modifier.fillMaxSize(),
                state = state,
                // room for the last disc to show whole, like the bottom of a real stack
                contentPadding = PaddingValues(start = 8.dp, end = 8.dp, top = 10.dp, bottom = full - STRIP + 10.dp),
            ) {
                itemsIndexed(tapes, key = { _, t -> t.id }) { i, t ->
                    val up = lifted == t.id
                    val h by animateDpAsState(if (up) full + 10.dp else STRIP, label = "disc")
                    val lift by animateFloatAsState(if (up) 1f else 0f, label = "lift")
                    Box(
                        Modifier.fillMaxWidth().height(h).zIndex(i.toFloat())
                    ) {
                        Disc(
                            t, full, lift,
                            selected = t.id in selected, playing = playing == t.id, progress = progress,
                            queued = t.id in queued, tidyAt = tidy[t.id], inDeck = inDeck == t.id, loadMode = loadMode,
                            onLoad = { onLoad(t) }, onPlay = { onTap(t) },
                            modifier = Modifier
                                .fillMaxWidth()
                                .wrapContentHeight(Alignment.Top, unbounded = true)
                                .requiredHeight(full)
                                .graphicsLayer {
                                    // pulled up and out of the stack, casting a shadow on the discs below
                                    translationY = -with(density) { 6.dp.toPx() } * lift
                                    translationX = with(density) { (-4).dp.toPx() } * lift
                                    shadowElevation = with(density) { 14.dp.toPx() } * lift
                                    this.shape = discShape(with(density) { CHAMFER.toPx() })
                                    clip = false
                                }
                                .combinedClickable(
                                    onClick = {
                                        when {
                                            selected.isNotEmpty() || up -> onTap(t)
                                            else -> { Feedback.detent(ctx); lifted = t.id }
                                        }
                                    },
                                    onLongClick = { onLong(t) },
                                ),
                        )
                    }
                }
            }
        }
        rail?.let { Box(Modifier.width(10.dp).fillMaxHeight().background(it)) }
    }
}

/** The cartridge outline: the clipped corner top-left, slightly rounded elsewhere. */
private fun discShape(cut: Float) = GenericShape { s, _ ->
    val r = cut * .35f
    moveTo(cut, 0f); lineTo(s.width - r, 0f); quadraticTo(s.width, 0f, s.width, r)
    lineTo(s.width, s.height - r); quadraticTo(s.width, s.height, s.width - r, s.height)
    lineTo(r, s.height); quadraticTo(0f, s.height, 0f, s.height - r)
    lineTo(0f, cut); close()
}

/** One MiniDisc, [full] tall; [lift] 0 (in the stack, label edge showing) to 1 (pulled out). */
@Composable
private fun Disc(
    t: Tape, full: Dp, lift: Float, selected: Boolean, playing: Boolean, progress: Float,
    queued: Boolean, tidyAt: Long?, inDeck: Boolean, loadMode: Boolean,
    onLoad: () -> Unit, onPlay: () -> Unit, modifier: Modifier,
) {
    val shell = shellOf(t)
    Box(modifier) {
        Canvas(Modifier.fillMaxSize()) {
            val w = size.width; val h = size.height
            val cut = CHAMFER.toPx()
            val r = cut * .35f
            val body = Path().apply {
                moveTo(cut, 0f); lineTo(w - r, 0f); quadraticTo(w, 0f, w, r)
                lineTo(w, h - r); quadraticTo(w, h, w - r, h)
                lineTo(r, h); quadraticTo(0f, h, 0f, h - r)
                lineTo(0f, cut); close()
            }
            drawPath(body, Brush.verticalGradient(listOf(lerp(shell, Color.White, .18f), shell, lerp(shell, Color.Black, .35f))))
            // glossy top edge
            drawPath(body, Brush.verticalGradient(listOf(Color.White.copy(alpha = .22f), Color.Transparent), endY = STRIP.toPx() * .6f))
            drawPath(body, if (selected) Color(0xFFFF3B4E) else Color.Black.copy(alpha = .55f), style = Stroke(if (selected) 3.dp.toPx() else 1.dp.toPx()))

            // Lower half: the disc showing through its slot, the metal shutter, write-protect tab.
            val top = h * .62f; val bottom = h - 10.dp.toPx()
            val slotL = w * .07f; val slotR = w * .6f
            drawRoundRect(Color.Black.copy(alpha = .6f), Offset(slotL, top), Size(slotR - slotL, bottom - top), androidx.compose.ui.geometry.CornerRadius(4.dp.toPx()))
            clipRect(slotL, top, slotR, bottom) {
                val cx = slotL + (slotR - slotL) * .72f; val cy = top - (bottom - top) * .1f
                val rr = (bottom - top) * 1.0f
                drawCircle(Brush.radialGradient(listOf(Color(0xFFFFE27A), Color(0xFFE0A91E), Color(0xFFB9860F)), Offset(cx, cy), rr), rr, Offset(cx, cy))
                drawCircle(Color.Black.copy(alpha = .25f), rr * .32f, Offset(cx, cy), style = Stroke(1.5.dp.toPx()))
            }
            val shL = slotL - 2.dp.toPx(); val shR = slotL + (slotR - slotL) * .52f
            drawRoundRect(
                Brush.verticalGradient(listOf(Color(0xFFE4E6E9), Color(0xFFA9ADB3), Color(0xFFCDD0D4), Color(0xFF8C9096)), top, bottom),
                Offset(shL, top - 3.dp.toPx()), Size(shR - shL, bottom - top + 6.dp.toPx()), androidx.compose.ui.geometry.CornerRadius(3.dp.toPx())
            )
            for (k in 1..3) {
                val gy = top + (bottom - top) * (.25f + k * .1f)
                drawLine(Color.Black.copy(alpha = .2f), Offset(shL + 8.dp.toPx(), gy), Offset(shL + (shR - shL) * .55f, gy), 1.5.dp.toPx())
            }
        }

        // The label: a strip in the stack; pulled out it shows everything.
        val labelH = STRIP - 12.dp + (full * .62f - STRIP - 4.dp) * lift
        Column(
            Modifier
                .padding(start = CHAMFER + 6.dp, end = 8.dp, top = 6.dp)
                .fillMaxWidth()
                .height(labelH)
                .clip(RoundedCornerShape(3.dp))
                .background(Deck.cream)
        ) {
            Row(Modifier.fillMaxWidth().height(STRIP - 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.width(10.dp).fillMaxHeight()) {
                    Deck.stripes.forEach { Box(Modifier.weight(1f).fillMaxHeight().background(it)) }
                }
                Spacer(Modifier.width(6.dp))
                if (selected || playing) Text(
                    if (selected) "✔ " else "■ ", color = Deck.red, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 13.sp
                )
                if (t.title.isBlank()) TitleText("", "${t.date}  ${t.time}", Deck.ink, 13f, Modifier.weight(1f))
                else Column(Modifier.weight(1f)) {
                    TitleText(t.title, "", Deck.ink, 12f)
                    if (lift < .5f) Text(
                        "${t.date}  ${t.time}", color = Deck.ink.copy(alpha = .7f), fontFamily = Mono,
                        fontSize = 10.sp, lineHeight = 11.sp, maxLines = 1
                    )
                }
                if (lift < .5f) {
                    if (inDeck) { Badge("◉", Deck.cream, Deck.ink); Spacer(Modifier.width(4.dp)) }
                    if (t.isNew) { Badge(stringResource(R.string.badge_new), Color.White, Deck.red); Spacer(Modifier.width(4.dp)) }
                    CcBadge(t.cc, queued, Deck.ink)
                }
                Text(TapeNames.duration(t.durationMs), color = Deck.ink, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                Spacer(Modifier.width(8.dp))
            }
            if (lift > 0f) Column(
                Modifier.fillMaxWidth().weight(1f).alpha(lift).padding(start = 16.dp, end = 8.dp, bottom = 4.dp),
                verticalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                Box(Modifier.fillMaxWidth().height(1.dp).background(Deck.ink.copy(alpha = .3f)))
                if (t.title.isNotBlank()) Text("${t.date}  ${t.time}", color = Deck.ink, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 13.sp, maxLines = 1)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (inDeck) { Badge(stringResource(R.string.badge_in_deck), Deck.cream, Deck.ink); Spacer(Modifier.width(6.dp)) }
                    if (t.isNew) { Badge(stringResource(R.string.badge_new), Color.White, Deck.red); Spacer(Modifier.width(6.dp)) }
                    TidyBadge(tidyAt)
                    CcBadge(t.cc, queued, Deck.ink)
                }
                Spacer(Modifier.weight(1f))
                if (playing) Box(Modifier.fillMaxWidth().height(4.dp).background(Deck.ink.copy(alpha = .15f))) {
                    Box(Modifier.fillMaxWidth(progress).fillMaxHeight().background(Deck.orange))
                }
            }
        }

        // Pulled out: keys beside the shutter.
        if (lift > .6f) Row(
            Modifier
                .align(Alignment.BottomEnd)
                .padding(end = 10.dp, bottom = 12.dp)
                .alpha((lift - .6f) / .4f),
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.End),
            verticalAlignment = Alignment.Bottom,
        ) {
            DeckKey(if (loadMode) "⏏" else if (playing) "■" else "▶", Modifier.width(56.dp), height = 44.dp, onClick = onPlay)
            if (!loadMode) Box(Modifier.size(46.dp, 44.dp)) { LoadKey(enabled = !inDeck, onClick = onLoad) }
        }
    }
}
