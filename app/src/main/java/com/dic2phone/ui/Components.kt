package com.dic2phone.ui

import com.dic2phone.R
import com.dic2phone.L
import androidx.compose.ui.res.stringResource
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import android.app.Activity
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import com.dic2phone.Feedback
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.TextButton
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import com.dic2phone.Prefs

/** Current theme colours. Reads are snapshot state, so the UI recomposes when the theme changes. */
object Deck {
    var palette by mutableStateOf(Themes.Walnut)

    val bg get() = palette.bgBottom
    val panel get() = palette.panel
    val chrome1 get() = palette.key1
    val chrome2 get() = palette.key2
    val keyText get() = palette.keyText
    val cream get() = palette.label
    val ink get() = palette.ink
    val orange get() = palette.accent
    val amber get() = palette.accent
    val red get() = palette.danger
    val led get() = palette.led
    val ledOff get() = palette.ledOff
    val text get() = palette.text
    val dim get() = palette.dim
    val stripes get() = palette.stripes
}

/**
 * The deck's lettering: Courier Prime, bundled, so it looks the same on every phone (Samsung's
 * font styles replace the system monospace font). Symbols it lacks (▶ ⚑ ⏏) fall back to the system.
 */
val Mono = FontFamily(
    Font(com.dic2phone.R.font.courier_prime_regular, FontWeight.Normal),
    Font(com.dic2phone.R.font.courier_prime_bold, FontWeight.Bold),
    Font(com.dic2phone.R.font.courier_prime_italic, FontWeight.Normal, FontStyle.Italic),
    Font(com.dic2phone.R.font.courier_prime_bold_italic, FontWeight.Bold, FontStyle.Italic),
)

/** The maker's badge lettering (Barlow), bundled for the same reason as [Mono]. */
val Brand = FontFamily(
    Font(com.dic2phone.R.font.barlow_black_italic, FontWeight.Black, FontStyle.Italic),
    Font(com.dic2phone.R.font.barlow_bold, FontWeight.Bold),
)

/** The pen font, for what the user wrote themselves (tape titles) when labels are handwritten. */
val Hand = FontFamily(Font(com.dic2phone.R.font.reenie_beanie))

/** Tape title text: handwritten or typed, as set in Setup → LOOK. Dates (no title) stay typed. */
@Composable
fun TitleText(title: String, fallback: String, color: Color, size: Float, modifier: Modifier = Modifier) {
    val typed by Prefs.labelTyped.collectAsState()
    if (title.isNotBlank() && !typed) Text(
        title, color = color, fontFamily = Hand, fontSize = (size * 1.45f).sp, lineHeight = (size * 1.45f).sp,
        maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis, modifier = modifier
    ) else Text(
        title.ifBlank { fallback }, color = color, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = size.sp,
        maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis, modifier = modifier
    )
}

/** Themed full-screen background (gradient + optional synthwave grid). */
fun Modifier.deckBackground(): Modifier = drawBehind {
    val p = Deck.palette
    drawIntoCanvas { DeckArt.background(it.nativeCanvas, size.width, size.height, p) }
}

/** Dark status/nav-bar icons on the light themes (Chrome, Beige). */
@Composable
fun ThemedSystemBars() {
    val view = LocalView.current
    val light = Deck.palette.bgTop.luminance() > .5f
    LaunchedEffect(light) {
        val w = (view.context as? Activity)?.window ?: return@LaunchedEffect
        WindowCompat.getInsetsController(w, view).apply {
            isAppearanceLightStatusBars = light
            isAppearanceLightNavigationBars = light
        }
    }
}

@Composable
fun BrandPlate(modifier: Modifier = Modifier) {
    val p = Deck.palette
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        // The logo keeps its size; the stripes either side of it give way when the plate is narrow.
        Row(verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f, fill = false).widthIn(max = 54.dp)) {
                p.stripes.forEach { Box(Modifier.weight(1f).height(4.dp).background(it)) }
            }
            Text(
                "DIC2PHONE",
                modifier = Modifier.padding(horizontal = 12.dp),
                style = TextStyle(
                    brush = Brush.verticalGradient(listOf(p.brand1, p.brand2, p.brand1, p.brand2)),
                    fontSize = 26.sp, fontFamily = Brand, fontWeight = FontWeight.Black, fontStyle = FontStyle.Italic,
                    letterSpacing = 3.sp,
                ),
                maxLines = 1, softWrap = false
            )
            Row(Modifier.weight(1f, fill = false).widthIn(max = 54.dp)) {
                p.stripes.reversed().forEach { Box(Modifier.weight(1f).height(4.dp).background(it)) }
            }
        }
        val disc by Prefs.minidisc.collectAsState()
        Text(
            if (disc) "STEREO MINIDISC RECORDER  DX-2" else "STEREO CASSETTE RECORDER  DX-2",
            color = Deck.dim, fontSize = 10.sp, fontFamily = Mono, letterSpacing = 1.sp,
            maxLines = 1, softWrap = false
        )
    }
}

/**
 * A mechanical piano key seen from slightly above: a top face, a darker front lip below it,
 * sitting in a black well. Pressing sinks the key: the face drops by its travel, most of the
 * front lip disappears into the chassis and a strip of the dark well opens up above it.
 * [down] (0..1) is how far the key is pressed; keep it animated for the "thunk".
 */
@Composable
fun PianoKey(
    down: Float,
    height: Dp,
    modifier: Modifier = Modifier,
    face1: Color = Deck.chrome1,
    face2: Color = Deck.chrome2,
    content: @Composable BoxScope.() -> Unit,
) {
    val lip = minOf(height * 0.2f, 14.dp)
    val travel = minOf(height * 0.08f, 6.dp)
    Box(
        modifier
            .height(height)
            .clip(RoundedCornerShape(3.dp))
            .background(Color(0xFF060606))
            .drawBehind {
                val w = size.width; val h = size.height
                val top = travel.toPx() * down
                val lipNow = lip.toPx() * (1f - 0.7f * down)
                val faceH = h - lipNow - top
                // top face, lit from above
                drawRect(
                    Brush.verticalGradient(listOf(face1, face2), startY = top, endY = top + faceH),
                    Offset(0f, top), Size(w, faceH)
                )
                // rounded side edges + less light once it's down in the well
                drawRect(
                    Brush.horizontalGradient(
                        0f to Color.Black.copy(alpha = .22f), .07f to Color.Transparent,
                        .93f to Color.Transparent, 1f to Color.Black.copy(alpha = .3f)
                    ),
                    Offset(0f, top), Size(w, faceH)
                )
                if (down > 0f) drawRect(Color.Black.copy(alpha = .16f * down), Offset(0f, top), Size(w, faceH))
                drawRect(Color.White.copy(alpha = .45f * (1f - .6f * down)), Offset(0f, top), Size(w, 1.5.dp.toPx()))
                // front lip
                drawRect(
                    Brush.verticalGradient(
                        listOf(lerp(face2, Color.Black, .35f), lerp(face2, Color.Black, .7f)),
                        startY = h - lipNow, endY = h
                    ),
                    Offset(0f, h - lipNow), Size(w, lipNow)
                )
                drawRect(Color.Black.copy(alpha = .5f), Offset(0f, h - lipNow), Size(w, 1.dp.toPx()))
            }
    ) {
        Box(
            Modifier
                .matchParentSize()
                .graphicsLayer { translationY = travel.toPx() * down }
                .padding(bottom = lip),
            contentAlignment = Alignment.Center,
            content = content
        )
    }
}

/** Quick, hard key travel with a tiny bounce at the bottom. */
@Composable
fun animateKeyDown(pressed: Boolean): Float =
    animateFloatAsState(
        if (pressed) 1f else 0f,
        spring(dampingRatio = .55f, stiffness = if (pressed) 3000f else 1400f),
        label = "key"
    ).value

/** Piano-key style button. */
@Composable
fun DeckKey(
    text: String,
    modifier: Modifier = Modifier,
    height: Dp = 52.dp,
    enabled: Boolean = true,
    textColor: Color? = null,
    onClick: () -> Unit,
) {
    val src = remember { MutableInteractionSource() }
    val pressed by src.collectIsPressedAsState()
    PianoKey(
        animateKeyDown(pressed), height,
        modifier
            .clickable(interactionSource = src, indication = null, enabled = enabled) {
                Feedback.key(); onClick()
            }
            .alpha(if (enabled) 1f else .4f)
    ) {
        Text(
            text, color = textColor ?: Deck.keyText, fontFamily = Mono, fontWeight = FontWeight.Bold,
            fontSize = 13.sp, letterSpacing = 1.sp, maxLines = 1
        )
    }
}

/**
 * For keys that are held (REC, REW, FF): waits for *this* finger to lift, wherever it has gone
 * meanwhile, swallowing its moves. Unlike a tap gesture, sliding off the key (or the key being
 * moved from under the finger) doesn't end the press. True once lifted; false if the touch
 * was cancelled (e.g. the system took it).
 */
suspend fun androidx.compose.ui.input.pointer.AwaitPointerEventScope.awaitLift(
    id: androidx.compose.ui.input.pointer.PointerId,
): Boolean {
    while (true) {
        val c = awaitPointerEvent().changes.firstOrNull { it.id == id } ?: return false
        c.consume()
        if (!c.pressed) return true
    }
}

/** One key of the deck's transport bank: label printed on the faceplate above it. */
class BankKey(
    val label: String,
    val glyph: String,
    val weight: Float = 1f,
    val labelColor: Color? = null,
    val face1: Color? = null,
    val face2: Color? = null,
    val glyphColor: Color? = null,
    /** Custom press handling (REC: hold). Gets the key's "is down" setter. */
    val press: (Modifier.(setDown: (Boolean) -> Unit) -> Modifier)? = null,
    val latched: Boolean = false,
    /** Drawn instead of [glyph] when set (in the glyph's colour). */
    val icon: (DrawScope.(Color) -> Unit)? = null,
    val onClick: () -> Unit = {},
)

/** The row of piano keys on the deck, like a portable recorder's transport. */
@Composable
fun KeyBank(keys: List<BankKey>, keyHeight: Dp, modifier: Modifier = Modifier) {
    val p = Deck.palette
    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(Brush.verticalGradient(listOf(lerp(p.panel, Color.White, .12f), p.panel)))
            .border(1.dp, Color.Black.copy(alpha = .5f), RoundedCornerShape(8.dp))
            .padding(horizontal = 8.dp, vertical = 6.dp)
    ) {
        Row(Modifier.fillMaxWidth().padding(bottom = 4.dp), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            keys.forEach { k ->
                // Translated labels can outgrow their key: shrink to fit rather than wrap/drop words.
                androidx.compose.foundation.text.BasicText(
                    k.label,
                    style = androidx.compose.ui.text.TextStyle(
                        color = k.labelColor ?: Deck.dim, fontFamily = Mono, fontWeight = FontWeight.Bold,
                        fontSize = 10.sp, letterSpacing = 1.sp, textAlign = TextAlign.Center
                    ),
                    maxLines = 1, softWrap = false,
                    autoSize = androidx.compose.foundation.text.TextAutoSize.StepBased(7.sp, 10.sp, 0.5.sp),
                    modifier = Modifier.weight(k.weight)
                )
            }
        }
        Row(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(4.dp))
                .background(Color(0xFF050505))
                .padding(3.dp),
            horizontalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            keys.forEach { k ->
                var held by remember { mutableStateOf(false) }
                val src = remember { MutableInteractionSource() }
                val pressed by src.collectIsPressedAsState()
                val input = k.press
                val mod = Modifier.weight(k.weight).let { m ->
                    if (input != null) m.input { held = it }
                    else m.clickable(interactionSource = src, indication = null) { Feedback.key(); k.onClick() }
                }
                PianoKey(
                    animateKeyDown(held || pressed || k.latched), keyHeight, mod,
                    face1 = k.face1 ?: Deck.chrome1, face2 = k.face2 ?: Deck.chrome2
                ) {
                    val c = k.glyphColor ?: Deck.keyText
                    val icon = k.icon
                    if (icon != null) Canvas(Modifier.size(26.dp, 22.dp)) { icon(c) }
                    else Text(k.glyph, color = c, fontFamily = Mono, fontWeight = FontWeight.Black, fontSize = 18.sp)
                }
            }
        }
    }
}

@Composable
fun Led(on: Boolean, modifier: Modifier = Modifier, size: Dp = 14.dp) {
    Box(
        modifier
            .size(size)
            .shadow(if (on) 8.dp else 0.dp, CircleShape, ambientColor = Deck.led, spotColor = Deck.led)
            .clip(CircleShape)
            .background(
                if (on) Brush.radialGradient(listOf(Color.White.copy(alpha = .8f), Deck.led))
                else Brush.radialGradient(listOf(Deck.ledOff, Color.Black.copy(alpha = .8f)))
            )
            .border(1.dp, Color.Black, CircleShape)
    )
}

/**
 * Mechanical 3-digit tape counter with rolling digits. With [onReset], a small square reset
 * button sits in the same window, right of the digits, like on a real deck.
 */
@Composable
fun TapeCounter(value: Int, modifier: Modifier = Modifier, onReset: (() -> Unit)? = null) {
    val p = Deck.palette
    val digits = value.coerceIn(0, 999).toString().padStart(3, '0')
    Row(
        modifier
            .clip(RoundedCornerShape(4.dp))
            .background(Color.Black)
            .border(2.dp, p.key2, RoundedCornerShape(4.dp))
            .padding(4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        digits.forEachIndexed { i, d ->
            key(i) {
                AnimatedContent(
                    targetState = d,
                    transitionSpec = { slideInVertically { -it } togetherWith slideOutVertically { it } },
                    label = "digit"
                ) { ch ->
                    Box(
                        Modifier
                            .padding(horizontal = 2.dp)
                            .size(30.dp, 42.dp)
                            .background(
                                Brush.verticalGradient(
                                    listOf(p.counterBg, Color(DeckArt.lighten(p.counterBg)), p.counterBg)
                                )
                            ),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            ch.toString(), color = p.counterDigit, fontFamily = Mono,
                            fontSize = 28.sp, fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
        if (onReset != null) {
            Spacer(Modifier.width(8.dp))
            CounterResetButton(onReset)
            Spacer(Modifier.width(4.dp))
        }
    }
}

/** The counter's little square plastic reset button: sinks when pressed. */
@Composable
private fun CounterResetButton(onClick: () -> Unit) {
    val p = Deck.palette
    val src = remember { MutableInteractionSource() }
    val pressed by src.collectIsPressedAsState()
    val down = animateKeyDown(pressed)
    val shape = RoundedCornerShape(3.dp)
    Box(
        Modifier
            .size(28.dp)
            .background(Color(0xFF050505), shape) // the hole it sits in
            .semantics { contentDescription = L.s(R.string.a11y_reset_counter) }
            .clickable(interactionSource = src, indication = null, role = Role.Button) {
                Feedback.key(); onClick()
            },
        contentAlignment = Alignment.Center
    ) {
        Box(
            Modifier
                .offset(x = (1.5f * down).dp, y = (2f * down).dp)
                .size(24.dp)
                .shadow((3f * (1 - down)).dp, shape)
                .background(
                    Brush.linearGradient(listOf(lerp(p.key1, Color.White, .15f), p.key2)), shape
                )
                .border(1.dp, Color.Black.copy(alpha = .6f), shape)
                .padding(4.dp)
                // worn top face of the cap
                .background(lerp(p.key1, p.key2, .35f + .25f * down), RoundedCornerShape(2.dp))
        )
    }
}

/**
 * Cassette drawing with spinning reels.
 * @param progress 0..1 how far the tape has wound from left reel to right reel.
 */
@Composable
fun CassetteView(
    label: String,
    sub: String,
    spinning: Boolean,
    progress: Float,
    modifier: Modifier = Modifier,
    side: String = "A",
    handwritten: Boolean = false,
) {
    var angle by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(spinning) {
        if (spinning) {
            var last = 0L
            while (true) {
                withFrameNanos { t ->
                    if (last != 0L) angle = (angle + (t - last) / 1e9f * 220f) % 360f
                    last = t
                }
            }
        }
    }
    val disc by Prefs.minidisc.collectAsState()
    val typed by Prefs.labelTyped.collectAsState()
    Canvas(modifier.aspectRatio(DeckArt.CASSETTE_RATIO)) {
        val p = Deck.palette
        DeckArt.typedLabels = typed
        drawIntoCanvas {
            if (disc) DeckArt.media(it.nativeCanvas, size.width, p, label, sub, angle, progress, spinning, true, handwritten)
            else DeckArt.cassette(it.nativeCanvas, size.width, p, label, sub, angle, progress, side, handwritten)
        }
    }
}

/** "Write on the label": edit the decorative text on the deck's tape / disc. */
@Composable
fun LabelDialog(onDismiss: () -> Unit) {
    var text by remember { mutableStateOf(Prefs.tapeLabel.value) }
    val disc = Prefs.minidisc.value
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Deck.panel,
        titleContentColor = Deck.text,
        title = { Text(stringResource(if (disc) R.string.label_title_disc else R.string.label_title_tape), fontFamily = Mono, fontWeight = FontWeight.Bold) },
        text = {
            OutlinedTextField(
                text, { text = it.take(Prefs.LABEL_MAX) },
                singleLine = true,
                placeholder = { Text(stringResource(R.string.label_hint), fontFamily = Mono, color = Deck.dim) },
                textStyle = TextStyle(fontFamily = Mono, fontWeight = FontWeight.Bold, color = Deck.text),
                supportingText = { Text(stringResource(R.string.label_count, text.length, Prefs.LABEL_MAX), fontFamily = Mono, color = Deck.dim) },
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { Prefs.setTapeLabel(text); onDismiss() }),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Deck.amber, unfocusedBorderColor = Deck.dim, cursorColor = Deck.amber
                ),
            )
        },
        confirmButton = {
            TextButton(onClick = { Prefs.setTapeLabel(text); onDismiss() }) {
                Text(stringResource(R.string.label_write), color = Deck.amber, fontFamily = Mono, fontWeight = FontWeight.Bold)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel), color = Deck.text, fontFamily = Mono) }
        }
    )
}

/** Backlit analog VU meter. level 0..1 */
@Composable
fun VuMeter(level: Float, modifier: Modifier = Modifier) {
    val needle by animateFloatAsState(level, spring(dampingRatio = .55f, stiffness = 260f), label = "vu")
    Canvas(modifier.aspectRatio(DeckArt.VU_RATIO)) {
        val p = Deck.palette
        drawIntoCanvas { DeckArt.vu(it.nativeCanvas, size.width, p, needle) }
    }
}

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Text(text, color = Deck.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 18.sp, letterSpacing = 2.sp)
        Spacer(Modifier.width(10.dp))
        Deck.stripes.forEach { Box(Modifier.size((42 / Deck.stripes.size).dp, 4.dp).background(it)) }
    }
}

@Composable
fun KeyRow(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Row(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(Color.Black.copy(alpha = .55f))
            .padding(6.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        content = content
    )
}

/** Key icons drawn by hand (no font has a good "stack of tapes" or "tape rack"). */
object KeyIcons {
    /** Three cassette cases lying in a stack, seen from the side. */
    val tapes: DrawScope.(Color) -> Unit = { c ->
        val w = size.width; val h = size.height
        val caseH = h * .24f; val gap = h * .1f
        val stroke = Stroke(width = h * .07f)
        for (i in 0..2) {
            val y = h - (i + 1) * caseH - i * gap
            val inset = if (i == 1) w * .1f else 0f   // the middle one sticks out a bit
            drawRoundRect(c, Offset(inset, y), Size(w - w * .1f, caseH), CornerRadius(h * .04f), style = stroke)
            drawRect(c, Offset(inset + w * .12f, y + caseH * .3f), Size(w * .32f, caseH * .4f))
        }
    }

    /** Three MiniDiscs fanned in a stack, the front one showing its label and shutter. */
    val discs: DrawScope.(Color) -> Unit = { c ->
        val w = size.width; val h = size.height
        val s = h * .66f                       // each disc is about square
        val stroke = Stroke(width = h * .07f)
        fun disc(x: Float, y: Float, filled: Boolean) {
            val cut = s * .16f
            val p = androidx.compose.ui.graphics.Path().apply {
                moveTo(x + cut, y); lineTo(x + s, y); lineTo(x + s, y + s); lineTo(x, y + s); lineTo(x, y + cut); close()
            }
            if (filled) {
                drawPath(p, c, style = stroke)
                // label band and shutter
                drawRect(c, Offset(x + s * .16f, y + s * .14f), Size(s * .68f, s * .2f))
                drawRect(c, Offset(x + s * .14f, y + s * .52f), Size(s * .5f, s * .34f), style = Stroke(width = h * .05f))
            } else drawPath(p, c, style = stroke)
        }
        val dx = (w - s) / 2
        val gap = h * .08f
        val mx = dx; val my = (h - s) / 2
        val fx = 0f; val fy = h - s
        // each disc hides the ones behind it (plus a little air around its edge)
        clipRect(fx - gap, fy - gap, fx + s + gap, fy + s + gap, androidx.compose.ui.graphics.ClipOp.Difference) {
            clipRect(mx - gap, my - gap, mx + s + gap, my + s + gap, androidx.compose.ui.graphics.ClipOp.Difference) {
                disc(dx * 2, 0f, false)
            }
            disc(mx, my, false)
        }
        disc(fx, fy, true)
    }

    /** A rack of upright tape spines, one leaning. */
    val shelf: DrawScope.(Color) -> Unit = { c ->
        val w = size.width; val h = size.height
        val board = h * .1f
        drawRect(c, Offset(0f, h - board), Size(w, board))
        val spineW = w * .13f; val gap = w * .045f
        for (i in 0..3) {
            val x = w * .04f + i * (spineW + gap)
            drawRect(c, Offset(x, h * .12f), Size(spineW, h * .78f - board * .0f))
        }
        rotate(18f, Offset(w * .96f, h - board)) {
            drawRect(c, Offset(w * .96f - spineW, h * .12f), Size(spineW, h * .78f))
        }
    }
}

/** Marks the selected option of a key group. */
fun sel(on: Boolean, s: String) = if (on) "● $s" else s
