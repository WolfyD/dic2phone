package com.dic2phone.ui

import com.dic2phone.R
import androidx.compose.ui.res.stringResource
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.foundation.layout.Box
import com.dic2phone.Cue
import com.dic2phone.Feedback
import com.dic2phone.Transcriber
import com.dic2phone.MetaStore
import com.dic2phone.Player
import com.dic2phone.Prefs
import com.dic2phone.Tape
import com.dic2phone.TapeEngine
import com.dic2phone.TapeMeta
import com.dic2phone.TapeNames
import com.dic2phone.TapeStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** The tape's metadata, reloaded whenever tapes change (null until first loaded). */
@Composable
fun rememberMeta(t: Tape): TapeMeta? {
    val ctx = LocalContext.current
    val v by TapeStore.version.collectAsStateWithLifecycle()
    return produceState<TapeMeta?>(null, t.id, t.vault, v) {
        value = withContext(Dispatchers.IO) { MetaStore.load(ctx, t) }
    }.value
}

/** Edits a tape's metadata off the main thread; tells the user if it couldn't be saved. */
private suspend fun editMeta(ctx: Context, t: Tape, change: (TapeMeta) -> TapeMeta) {
    val ok = withContext(Dispatchers.IO) {
        runCatching { MetaStore.update(ctx, t, change) }.onFailure { android.util.Log.w("DeckPlayer", "meta", it) }.isSuccess
    }
    if (!ok) Toast.makeText(ctx, ctx.getString(R.string.player_save_fail), Toast.LENGTH_SHORT).show()
}

/**
 * REW / FF: one tap winds 10 s. Holding keeps winding: by repeated 10 s skips, or with
 * TAPE WIND on, like a real deck (see [Player.windStart]) until the key is let go.
 */
private fun windKey(ctx: Context, deltaMs: Long): Modifier.((Boolean) -> Unit) -> Modifier = { setDown ->
    pointerInput(deltaMs) {
        coroutineScope {
            val keyScope = this
            // The press lasts until the finger lifts, even if it slides off the key: see [awaitLift].
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                down.consume()
                setDown(true)
                Feedback.key()
                val tapeWind = Prefs.tapeWind.value
                var held = false
                val timer = if (!tapeWind) {
                    Player.skip(ctx, deltaMs)
                    keyScope.launch {
                        delay(450)
                        while (true) { Player.skip(ctx, deltaMs); delay(160) }
                    }
                } else keyScope.launch {
                    delay(WIND_HOLD_MS); held = true; Player.windStart(ctx, if (deltaMs < 0) -1 else 1)
                }
                var released = false
                try { released = awaitLift(down.id) } finally {
                    timer.cancel()
                    if (tapeWind) {
                        if (held) { Player.windStop(ctx); Feedback.key() }
                        else if (released) Player.skip(ctx, deltaMs)
                    }
                    setDown(false)
                }
            }
        }
    }
}

/** Longer than this is a hold (TAPE WIND), shorter a tap. */
private const val WIND_HOLD_MS = 300L

/**
 * TAPE WIND's CUE switch: an LED with CUE printed under it, and a little slide switch beside it.
 * Lit, winding lets you hear the tape. A tap anywhere on it flicks the switch.
 */
@Composable
private fun CueSwitch(modifier: Modifier = Modifier) {
    val ctx = LocalContext.current
    val on by Prefs.windCue.collectAsStateWithLifecycle()
    val knob by animateFloatAsState(if (on) 1f else 0f, spring(dampingRatio = .7f, stiffness = 1600f), label = "cue")
    Row(
        modifier
            .height(40.dp)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                Feedback.detent(ctx); Prefs.setWindCue(!on)
            },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Led(on, size = 9.dp)
            Text("CUE", color = Deck.dim, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 9.sp, letterSpacing = 1.sp, maxLines = 1)
        }
        // Slide switch: a slot in the faceplate with a ribbed chrome nub riding in it.
        Canvas(Modifier.width(30.dp).height(16.dp)) {
            val w = size.width; val h = size.height
            drawRoundRect(Color.Black, Offset.Zero, size, CornerRadius(3.dp.toPx()))
            val pad = 2.dp.toPx()
            val nw = w * 0.5f; val nh = h - 2 * pad
            val x = pad + (w - nw - 2 * pad) * knob
            drawRoundRect(
                Brush.verticalGradient(listOf(Deck.chrome1, Deck.chrome2), startY = pad, endY = pad + nh),
                Offset(x, pad), Size(nw, nh), CornerRadius(2.dp.toPx())
            )
            for (i in 1..3) {
                val rx = x + nw * i / 4f
                drawLine(Color.Black.copy(alpha = .35f), Offset(rx, pad + 2.dp.toPx()), Offset(rx, pad + nh - 2.dp.toPx()), 1.dp.toPx())
            }
        }
    }
}

/**
 * The deck as a player, for the tape that's been put in: scrub strip with the flags on it (and
 * the CUE switch), the time window beside the varispeed, live captions, a fold-up compartment
 * (previous / next flag, TRANSCRIBE, INFO) and the transport keys.
 */
@Composable
fun DeckPlayer(t: Tape, keyHeight: Dp, compact: Boolean = false, modifier: Modifier = Modifier) {
    val ctx = LocalContext.current
    val playing by Player.playingId.collectAsStateWithLifecycle()
    val pos by Player.deckPos.collectAsStateWithLifecycle()
    val isPlaying = playing == t.id
    val meta = rememberMeta(t)
    val flags = meta?.flags.orEmpty()
    val cues = rememberCues(t)
    var info by remember { mutableStateOf(false) }
    // Compact (sideways): the transport keys sit in the deck's own key row instead, see [transportKeys].
    val transport = if (compact) null else transportKeys(t)
    if (info) MetaDialog(t) { info = false }
    val captions = rememberCaptionStarter()
    captions.Dialogs()

    // Going back from just after a flag goes to the one before it, like a CD's |◀◀.
    val prev = flags.lastOrNull { it < pos - 1500 }
    val next = flags.firstOrNull { it > pos + 300 }
    // The flag just passed (within half a minute): its note shows on the counter, a tap edits it.
    val here = flags.lastOrNull { it <= pos + 300 }?.takeIf { pos - it < 30_000 }
    val hereNote = here?.let { meta?.note(it) }.orEmpty()
    var noting by remember { mutableStateOf<Long?>(null) }
    noting?.let { f -> FlagNoteDialog(t, f, meta?.note(f).orEmpty()) { noting = null } }

    Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        val wind by Prefs.tapeWind.collectAsStateWithLifecycle()
        // The slim position strip, with TAPE WIND's CUE switch beside it.
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ScrubStrip(
                t.durationMs, pos, flags, Modifier.weight(1f),
                onFlagHold = { noting = it },
            ) { Player.seek(ctx, it) }
            if (wind) CueSwitch(Modifier.width(72.dp))
        }
        // Time window and varispeed share the next line.
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(
                Modifier.weight(1f).let { m -> if (here != null) m.clickable { noting = here } else m },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                TimeWindow(pos, t.durationMs, flags.size, isPlaying)
                // Its line is always there (blank off a flag), so winding past flags moves nothing.
                Text(
                    if (here == null) "" else "⚑ " + hereNote.ifBlank { stringResource(R.string.player_add_note) },
                    color = if (hereNote.isBlank()) Deck.dim else Deck.amber,
                    fontFamily = Mono, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis
                )
            }
            VarispeedFader(Modifier.width(150.dp))
        }
        DeckCaptions(t, cues, pos)
        // The less-used keys live under a hinged lid, like the hidden controls on a real deck.
        Compartment {
            DeckKey("◀⚑", Modifier.weight(1f), height = 38.dp, enabled = prev != null) { prev?.let { Player.seek(ctx, it) } }
            DeckKey("⚑▶", Modifier.weight(1f), height = 38.dp, enabled = next != null) { next?.let { Player.seek(ctx, it) } }
            val queued by Transcriber.queued.collectAsStateWithLifecycle()
            if (!t.cc && cues == null && t.id !in queued) {
                DeckKey(stringResource(R.string.player_transcribe), Modifier.weight(1.8f), height = 38.dp) { captions.start(listOf(t)) }
            }
            DeckKey(stringResource(R.string.info), Modifier.weight(1.1f), height = 38.dp) { info = true }
        }
        transport?.let { KeyBank(it, keyHeight) }
    }
}

/**
 * The play time in a little recessed display window, like the counter's: position / length,
 * and the flag count. The digits light up while the tape plays.
 */
@Composable
private fun TimeWindow(pos: Long, dur: Long, flags: Int, playing: Boolean) {
    val p = Deck.palette
    val shape = androidx.compose.foundation.shape.RoundedCornerShape(4.dp)
    Row(
        Modifier
            .clip(shape)
            .background(Brush.verticalGradient(listOf(Color.Black, p.counterBg, Color.Black)))
            .border(2.dp, p.key2, shape)
            .padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val lit = if (playing) Deck.led else p.counterDigit
        Text(
            TapeNames.duration(pos), color = lit, fontFamily = Mono, fontWeight = FontWeight.Bold,
            fontSize = 18.sp, maxLines = 1
        )
        Text(
            " / " + TapeNames.duration(dur), color = lit.copy(alpha = .55f), fontFamily = Mono, fontWeight = FontWeight.Bold,
            fontSize = 12.sp, maxLines = 1
        )
        if (flags > 0) Text(
            "  ⚑$flags", color = Deck.red, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 12.sp, maxLines = 1
        )
    }
}

/** Whether the deck's compartment lid is up; kept while the app runs. */
private val lidOpen = mutableStateOf(false)

/**
 * A fold-up compartment: a thin hinged lid with a finger notch. Tap it and it flips up to show
 * the keys inside ([content], laid out in a row); tap the lid again to close it.
 */
@Composable
private fun Compartment(content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit) {
    val ctx = LocalContext.current
    var open by lidOpen
    // The flip: the lid squashes up towards its hinge, swaps to its underside, and drops back.
    val flip by animateFloatAsState(if (open) 1f else 0f, spring(dampingRatio = .8f, stiffness = 500f), label = "lid")
    val p = Deck.palette
    Column(Modifier.fillMaxWidth()) {
        val inside = flip > .5f
        Box(
            Modifier
                .fillMaxWidth()
                .height(22.dp)
                .graphicsLayer {
                    scaleY = kotlin.math.abs(1f - 2f * flip).coerceAtLeast(.08f)
                    transformOrigin = androidx.compose.ui.graphics.TransformOrigin(.5f, if (inside) 1f else 0f)
                }
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                    Feedback.detent(ctx); open = !open
                }
        ) {
            Canvas(Modifier.matchParentSize()) {
                val w = size.width; val h = size.height
                val r = CornerRadius(4.dp.toPx())
                val face = if (inside) listOf(lerp(p.panel, Color.Black, .45f), lerp(p.panel, Color.Black, .25f))
                else listOf(lerp(p.panel, Color.White, .14f), lerp(p.panel, Color.Black, .1f))
                drawRoundRect(Brush.verticalGradient(face), Offset.Zero, size, r)
                drawRoundRect(Color.Black.copy(alpha = .55f), Offset.Zero, size, r, style = Stroke(1.dp.toPx()))
                // Hinge line along the top (closed) or bottom (open).
                val hy = if (inside) h - 2.dp.toPx() else 2.dp.toPx()
                drawLine(Color.Black.copy(alpha = .4f), Offset(6.dp.toPx(), hy), Offset(w - 6.dp.toPx(), hy), 1.dp.toPx())
                // Finger notch in the lid's front edge.
                val nw = 46.dp.toPx(); val nh = 6.dp.toPx()
                drawRoundRect(
                    Color.Black.copy(alpha = .55f),
                    Offset((w - nw) / 2, if (inside) 0f else h - nh), Size(nw, nh), CornerRadius(nh / 2)
                )
            }
            Text(
                (if (inside) "▴  " else "▾  ") + stringResource(R.string.deck_lid),
                Modifier.align(Alignment.CenterStart).padding(start = 12.dp),
                color = Deck.dim, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 9.sp, letterSpacing = 1.5.sp, maxLines = 1
            )
        }
        androidx.compose.animation.AnimatedVisibility(
            open,
            enter = androidx.compose.animation.expandVertically(expandFrom = Alignment.Top),
            exit = androidx.compose.animation.shrinkVertically(shrinkTowards = Alignment.Top),
        ) {
            // The well under the lid: dark, the keys sitting in it.
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(top = 3.dp)
                    .clip(androidx.compose.foundation.shape.RoundedCornerShape(4.dp))
                    .background(Color(0xFF050505))
                    .padding(4.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically,
                content = content,
            )
        }
    }
}

/** REW · PLAY · FF · FLAG · EJECT for the tape in the deck. */
@Composable
fun transportKeys(t: Tape): List<BankKey> {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val playing by Player.playingId.collectAsStateWithLifecycle()
    val isPlaying = playing == t.id
    val pos by Player.deckPos.collectAsStateWithLifecycle()
    val flags = rememberMeta(t)?.flags.orEmpty()
    /** The flag just set: for 3 s the FLAG key takes it back. */
    var justFlagged by remember(t.id) { mutableStateOf<Long?>(null) }
    LaunchedEffect(justFlagged) { if (justFlagged != null) { delay(3000); justFlagged = null } }
    // Sitting on a flag (just jumped to it, or a moment past it): FLAG becomes UNFLAG and takes it off.
    val onFlag = justFlagged ?: flags.lastOrNull { it in pos - ON_FLAG_MS..pos + 300 }
    return listOf(
        BankKey(stringResource(R.string.key_rew), "◀◀", press = windKey(ctx, -10_000)),
        BankKey(
            stringResource(if (isPlaying) R.string.key_pause else R.string.key_play), if (isPlaying) "❚❚" else "▶", weight = 1.4f,
            latched = isPlaying, glyphColor = if (isPlaying) Deck.led else null,
        ) { Player.playPause(ctx) },
        BankKey(stringResource(R.string.key_ff), "▶▶", press = windKey(ctx, 10_000)),
        BankKey(stringResource(if (onFlag != null) R.string.key_unflag else R.string.key_flag), "⚑", labelColor = if (onFlag != null) Deck.orange else null) {
            val undo = onFlag
            if (undo != null) {
                justFlagged = null
                scope.launch { editMeta(ctx, t) { m -> m.copy(flags = m.flags - undo, flagNotes = m.flagNotes - undo) } }
            } else {
                val at = (Player.deckPos.value - TapeEngine.FLAG_LEAD_MS).coerceAtLeast(0)
                justFlagged = at
                scope.launch { editMeta(ctx, t) { m -> m.copy(flags = (m.flags + at).distinct().sorted()) } }
            }
        },
        BankKey(stringResource(R.string.key_eject), "⏏") { Feedback.doorOpen(ctx); Player.eject() },
    )
}

/** How far past a flag the deck still counts as "on" it (FLAG then removes it). */
private const val ON_FLAG_MS = 2500L

/**
 * The subtitle window: what's being said right now, or how far along the transcript is.
 * Empty for a tape that has no transcript yet (its TRANSCRIBE key sits in the row below).
 */
@Composable
private fun DeckCaptions(t: Tape, cues: List<Cue>?, pos: Long) {
    val queued by Transcriber.queued.collectAsStateWithLifecycle()
    val status by Transcriber.status.collectAsStateWithLifecycle()
    @Composable
    // Same height as the captions, so nothing shifts when they arrive.
    fun note(text: String, color: Color = Deck.dim) = Box(Modifier.fillMaxWidth().height(captionHeight()), contentAlignment = Alignment.Center) {
        Text(text, color = color, fontFamily = Mono, fontSize = 12.sp, textAlign = TextAlign.Center, maxLines = 2)
    }
    when {
        !cues.isNullOrEmpty() -> CaptionLine(cues, pos)
        cues != null -> note(stringResource(R.string.player_no_speech))
        t.id in queued -> {
            val s = status?.takeIf { it.tapeId == t.id }
            note(if (s != null) stringResource(R.string.player_transcribing, s.line, s.pct) else stringResource(R.string.player_cc_waiting), Deck.led)
        }
        t.cc -> note("")   // still reading it
        else -> {}
    }
}

/**
 * Tape position bar: tap or drag to wind there. Flags are the red marks: a tap near one jumps
 * straight to it, holding one opens its note ([onFlagHold]).
 */
@Composable
fun ScrubStrip(
    durMs: Long, posMs: Long, flags: List<Long>, modifier: Modifier = Modifier,
    onFlagHold: ((Long) -> Unit)? = null, onSeek: (Long) -> Unit,
) {
    var drag by remember { mutableStateOf<Float?>(null) }
    val dur = durMs.coerceAtLeast(1)
    val frac = drag ?: (posMs.toFloat() / dur).coerceIn(0f, 1f)
    val ctx = LocalContext.current
    Canvas(
        modifier
            .fillMaxWidth()
            .height(30.dp)
            .pointerInput(dur, flags) {
                /** The flag under a touch at [x], if any (the nearest within a fingertip). */
                fun flagAt(x: Float): Long? {
                    val reach = 16.dp.toPx()
                    return flags.minByOrNull { kotlin.math.abs(it.toFloat() / dur * size.width - x) }
                        ?.takeIf { kotlin.math.abs(it.toFloat() / dur * size.width - x) <= reach }
                }
                detectTapGestures(
                    onLongPress = { o -> flagAt(o.x)?.let { f -> onFlagHold?.let { Feedback.detent(ctx); it(f) } } },
                ) { o ->
                    val f = flagAt(o.x)
                    if (f != null) { Feedback.detent(ctx); onSeek(f) } else onSeek((o.x / size.width * dur).toLong())
                }
            }
            .pointerInput(dur) {
                detectHorizontalDragGestures(
                    onDragStart = { o -> drag = (o.x / size.width).coerceIn(0f, 1f) },
                    onDragEnd = { drag?.let { onSeek((it * dur).toLong()) }; drag = null },
                    onDragCancel = { drag = null },
                ) { change, _ -> drag = (change.position.x / size.width).coerceIn(0f, 1f) }
            }
    ) {
        val w = size.width; val h = size.height
        val top = h * 0.42f; val th = h * 0.32f
        val r = CornerRadius(th / 2, th / 2)
        drawRoundRect(Color.Black, Offset(0f, top), Size(w, th), r)
        drawRoundRect(Deck.amber, Offset(0f, top), Size(w * frac, th), r)
        flags.forEach { f ->
            val x = (f.toFloat() / dur).coerceIn(0f, 1f) * w
            val p = Path().apply {
                moveTo(x - 6.dp.toPx(), 0f); lineTo(x + 6.dp.toPx(), 0f); lineTo(x, top - 2.dp.toPx()); close()
            }
            drawPath(p, Deck.red)
            drawRect(Deck.red, Offset(x - 1.dp.toPx(), top), Size(2.dp.toPx(), th))
        }
        val x = frac * w
        drawRect(Deck.text, Offset(x - 2.dp.toPx(), top - 3.dp.toPx()), Size(4.dp.toPx(), th + 6.dp.toPx()))
    }
}

/** Write on a tape's label: its title (blank goes back to the date it was recorded). */
@Composable
fun TapeTitleDialog(t: Tape, onDismiss: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var text by remember(t.id) { mutableStateOf(t.title) }
    val save = {
        val v = text.trim()
        scope.launch { editMeta(ctx.applicationContext, t) { it.copy(title = v) }; onDismiss() }
        Unit
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Deck.panel,
        titleContentColor = Deck.text,
        title = {
            val disc by Prefs.minidisc.collectAsStateWithLifecycle()
            Text(stringResource(if (disc) R.string.label_title_disc else R.string.label_title_tape), fontFamily = Mono, fontWeight = FontWeight.Bold)
        },
        text = {
            OutlinedTextField(
                text, { text = it.take(TITLE_MAX) }, singleLine = true,
                placeholder = { Text(t.pretty, fontFamily = Mono, color = Deck.dim) },
                textStyle = TextStyle(fontFamily = Mono, fontWeight = FontWeight.Bold, color = Deck.text),
                supportingText = { Text("${text.length}/$TITLE_MAX", fontFamily = Mono, color = Deck.dim) },
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.Sentences, imeAction = androidx.compose.ui.text.input.ImeAction.Done
                ),
                keyboardActions = androidx.compose.foundation.text.KeyboardActions(onDone = { save() }),
                colors = fieldColors(),
            )
        },
        confirmButton = {
            TextButton(onClick = save) { Text(stringResource(R.string.label_write), color = Deck.amber, fontFamily = Mono, fontWeight = FontWeight.Bold) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel), color = Deck.text, fontFamily = Mono) } }
    )
}

private const val TITLE_MAX = 60

/** A note on one flag. */
@Composable
private fun FlagNoteDialog(t: Tape, flag: Long, current: String, onDismiss: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var text by remember { mutableStateOf(current) }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Deck.panel,
        titleContentColor = Deck.text,
        title = { Text("⚑ ${TapeNames.duration(flag)}", fontFamily = Mono, fontWeight = FontWeight.Bold) },
        text = {
            OutlinedTextField(
                text, { text = it.take(FLAG_NOTE_MAX) }, singleLine = true,
                textStyle = TextStyle(fontFamily = Mono, color = Deck.text, fontSize = 14.sp), colors = fieldColors(),
                label = { Text(stringResource(R.string.player_flag_note), fontFamily = Mono) },
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            )
        },
        confirmButton = {
            TextButton(onClick = {
                val v = text.trim()
                scope.launch {
                    editMeta(ctx.applicationContext, t) { it.copy(flagNotes = it.flagNotes - flag + (if (v.isEmpty()) emptyMap() else mapOf(flag to v))) }
                    onDismiss()
                }
            }) { Text(stringResource(R.string.save), color = Deck.amber, fontFamily = Mono, fontWeight = FontWeight.Bold) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel), color = Deck.text, fontFamily = Mono) } }
    )
}

private const val FLAG_NOTE_MAX = 120

@Composable
private fun fieldColors() = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = Deck.amber, unfocusedBorderColor = Deck.dim, cursorColor = Deck.amber,
    focusedTextColor = Deck.text, unfocusedTextColor = Deck.text,
)

/** What's written on a tape and what the deck knows about it. Title, notes, tags and flag notes are editable. */
@Composable
fun MetaDialog(t: Tape, onDismiss: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val meta = rememberMeta(t)
    var title by remember { mutableStateOf<String?>(null) }
    var notes by remember { mutableStateOf<String?>(null) }
    var tags by remember { mutableStateOf<String?>(null) }
    var fnotes by remember { mutableStateOf<Map<Long, String>>(emptyMap()) }
    LaunchedEffect(meta != null) {
        if (meta != null && title == null) {
            title = meta.title; notes = meta.notes; tags = meta.tags.joinToString(", ")
            fnotes = meta.flagNotes
        }
    }
    val colors = fieldColors()
    val style = TextStyle(fontFamily = Mono, color = Deck.text, fontSize = 14.sp)
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Deck.panel,
        titleContentColor = Deck.text,
        title = { Text(stringResource(R.string.meta_title), fontFamily = Mono, fontWeight = FontWeight.Bold) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (meta == null) { Text("…", color = Deck.dim, fontFamily = Mono); return@Column }
                OutlinedTextField(
                    title.orEmpty(), { title = it.take(60) }, singleLine = true, textStyle = style, colors = colors,
                    label = { Text(stringResource(R.string.meta_f_title), fontFamily = Mono) },
                    placeholder = { Text(t.pretty, fontFamily = Mono, color = Deck.dim) },
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                )
                OutlinedTextField(
                    notes.orEmpty(), { notes = it.take(4000) }, textStyle = style, colors = colors,
                    minLines = 2, maxLines = 6, label = { Text(stringResource(R.string.meta_f_notes), fontFamily = Mono) },
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                )
                OutlinedTextField(
                    tags.orEmpty(), { tags = it.take(300) }, singleLine = true, textStyle = style, colors = colors,
                    label = { Text(stringResource(R.string.meta_f_tags), fontFamily = Mono) },
                    placeholder = { Text(stringResource(R.string.meta_f_tags_hint), fontFamily = Mono, color = Deck.dim) },
                )
                meta.flags.forEach { f ->
                    OutlinedTextField(
                        fnotes[f].orEmpty(), { fnotes = fnotes + (f to it.take(FLAG_NOTE_MAX)) }, singleLine = true,
                        textStyle = style, colors = colors,
                        label = { Text(stringResource(R.string.meta_f_flag_note, TapeNames.duration(f)), fontFamily = Mono) },
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                    )
                }
                Facts(ctx, t, meta)
            }
        },
        confirmButton = {
            TextButton(enabled = meta != null, onClick = {
                val newTags = tags.orEmpty().split(',', '#').map { it.trim() }.filter { it.isNotEmpty() }
                    .distinctBy { it.lowercase() }.take(TapeMeta.TAGS_MAX)
                val ti = title.orEmpty().trim(); val no = notes.orEmpty().trim()
                val fn = fnotes.mapValues { it.value.trim() }.filterValues { it.isNotEmpty() }
                scope.launch {
                    editMeta(ctx.applicationContext, t) { it.copy(title = ti, notes = no, tags = newTags, flagNotes = fn) }
                    onDismiss()
                }
            }) { Text(stringResource(R.string.save), color = Deck.amber, fontFamily = Mono, fontWeight = FontWeight.Bold) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel), color = Deck.text, fontFamily = Mono) } }
    )
}

@Composable
private fun Facts(ctx: Context, t: Tape, m: TapeMeta) {
    @Composable
    fun fact(k: String, v: String, onClick: (() -> Unit)? = null) {
        Row(Modifier.fillMaxWidth().heightIn(min = 20.dp).let { if (onClick != null) it.clickable(onClick = onClick) else it }) {
            Text(k, color = Deck.dim, fontFamily = Mono, fontSize = 11.sp, modifier = Modifier.width(96.dp).padding(top = 1.dp))
            Text(v, color = if (onClick != null) Deck.amber else Deck.text, fontFamily = Mono, fontSize = 12.sp, modifier = Modifier.weight(1f))
        }
    }
    Column(Modifier.padding(top = 6.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        fact(stringResource(R.string.meta_recorded), if (m.startedAt > 0) MetaStore.clock(m.startedAt) else t.pretty)
        if (m.endedAt > 0) fact(stringResource(R.string.meta_ended), MetaStore.clock(m.endedAt))
        fact(stringResource(R.string.meta_length), TapeNames.duration(m.durationMs.takeIf { it > 0 } ?: t.durationMs) + if (m.part > 0) "  ·  " + stringResource(R.string.meta_part, m.part) else "")
        fact(stringResource(R.string.meta_size), MetaStore.size(t.sizeBytes.takeIf { it > 0 } ?: m.sizeBytes))
        fact(stringResource(R.string.meta_format), m.format.ifBlank { "AAC · .m4a" })
        if (m.peakDb != null) fact(stringResource(R.string.meta_level), stringResource(R.string.meta_level_v, m.peakDb, m.avgDb ?: -96f))
        if (m.source.isNotBlank()) fact(stringResource(R.string.meta_started_by), MetaStore.source(m.source))
        val mode = listOfNotNull(
            if (m.latched) stringResource(R.string.meta_mode_locked) else if (m.source.isNotBlank()) stringResource(R.string.meta_mode_held) else null,
            if (m.vox) stringResource(R.string.meta_mode_vox) + (if (m.cuts > 0) ", " + stringResource(R.string.meta_mode_cuts, m.cuts, TapeNames.duration(m.skippedMs)) else "") else null,
        )
        if (mode.isNotEmpty()) fact(stringResource(R.string.meta_mode), mode.joinToString(" · "))
        if (m.hasPlace) {
            val label = m.place.ifBlank { MetaStore.coords(m.lat!!, m.lon!!) }
            fact(stringResource(R.string.meta_place), label + (if (m.place.isNotBlank()) "\n" + MetaStore.coords(m.lat!!, m.lon!!) else "") +
                (m.accuracyM?.let { "  ±${it.toInt()} m" } ?: "")) {
                runCatching {
                    ctx.startActivity(
                        Intent(Intent.ACTION_VIEW, Uri.parse("geo:${m.lat},${m.lon}?q=${m.lat},${m.lon}(${Uri.encode(label)})"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                }.onFailure { Toast.makeText(ctx, ctx.getString(R.string.meta_no_maps), Toast.LENGTH_SHORT).show() }
            }
        }
        if (m.flags.isEmpty()) fact(stringResource(R.string.meta_flags), stringResource(R.string.meta_none))
        if (m.device.isNotBlank()) fact(stringResource(R.string.meta_device), m.device)
        fact(stringResource(R.string.meta_file), t.id + when {
            t.vault != null -> "  " + stringResource(R.string.meta_in_vault)
            t.file != null -> "  " + stringResource(R.string.meta_in_deck)
            else -> "  " + stringResource(R.string.meta_in_shelf)
        })
    }
}
