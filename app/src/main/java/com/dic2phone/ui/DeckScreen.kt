package com.dic2phone.ui

import com.dic2phone.R
import com.dic2phone.L
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import com.dic2phone.Feedback
import com.dic2phone.Prefs
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.Dp
import android.os.SystemClock
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.dic2phone.Player
import com.dic2phone.Recorder
import com.dic2phone.RecorderService
import com.dic2phone.Tape
import com.dic2phone.TapeNames
import com.dic2phone.TapeStore
import com.dic2phone.Vault
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/** LOAD: the deck's tapes, opened by tapping the cassette window; a tap puts a tape in. */
enum class Screen { DECK, TAPES, LOAD, SHELF, VAULT, SEARCH, SETUP }

/** Where tapes live: on the deck (app storage), the shelf (public Recordings) or the vault. */
enum class Shelf { DECK, SHELF, VAULT }

@Composable
fun rememberTapes(kind: Shelf): State<List<Tape>?> {
    val ctx = LocalContext.current
    val v by TapeStore.version.collectAsStateWithLifecycle()
    return produceState<List<Tape>?>(null, v, kind) {
        value = withContext(Dispatchers.IO) {
            when (kind) {
                Shelf.DECK -> TapeStore.deck(ctx)
                Shelf.SHELF -> TapeStore.shelf(ctx)
                Shelf.VAULT -> Vault.list(ctx)
            }
        }
    }
}

/** Milliseconds since recording started, ticking while recording. */
@Composable
fun rememberElapsed(rec: Recorder.State): Long {
    var now by remember { mutableLongStateOf(SystemClock.elapsedRealtime()) }
    LaunchedEffect(rec.recording) {
        while (rec.recording) { now = SystemClock.elapsedRealtime(); delay(200) }
    }
    return if (rec.recording) (now - rec.startedAt).coerceAtLeast(0) else 0L
}

fun hasMic(ctx: Context) =
    ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun DeckScreen(onNav: (Screen) -> Unit) {
    val ctx = LocalContext.current
    val rec by Recorder.state.collectAsStateWithLifecycle()
    val tapes by rememberTapes(Shelf.DECK)
    val list = tapes.orEmpty()
    val newCount = list.count { it.isNew }
    val elapsed = rememberElapsed(rec)

    val perms = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {}
    LaunchedEffect(Unit) {
        val need = buildList {
            if (!hasMic(ctx)) add(Manifest.permission.RECORD_AUDIO)
            if (android.os.Build.VERSION.SDK_INT >= 33 &&
                ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) add(Manifest.permission.POST_NOTIFICATIONS)
        }
        if (need.isNotEmpty()) perms.launch(need.toTypedArray())
    }

    val landscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
    val needMic = { perms.launch(arrayOf(Manifest.permission.RECORD_AUDIO)) }

    // The tape in the deck: put back after a restart, kept up to date (title, flags), ejected if gone.
    val loaded by Player.loaded.collectAsStateWithLifecycle()
    val version by TapeStore.version.collectAsStateWithLifecycle()
    LaunchedEffect(version) {
        val cur = Player.loaded.value
        val want = cur?.id ?: Prefs.deckTape.takeIf { it.isNotBlank() } ?: return@LaunchedEffect
        val found = withContext(Dispatchers.IO) {
            if (cur?.vault != null) Vault.list(ctx).firstOrNull { it.vault == cur.vault }
            else (TapeStore.deck(ctx) + TapeStore.shelf(ctx)).firstOrNull { it.id == want }
        }
        if (cur == null) { if (found != null) Player.load(found) else Prefs.deckTape = "" }
        else Player.refresh(found)
    }
    // Playing with tape effects: get the deck tape's effects copy ready before PLAY is pressed.
    val fxPlay by Prefs.fxPlay.collectAsStateWithLifecycle()
    val fx by Prefs.fx.collectAsStateWithLifecycle()
    LaunchedEffect(loaded?.id, fxPlay, fx) {
        val t = loaded ?: return@LaunchedEffect
        if (fxPlay && fx.any && t.vault == null) com.dic2phone.LoFi.warm(ctx, t, fx)
    }
    val playingId by Player.playingId.collectAsStateWithLifecycle()
    val deckPos by Player.deckPos.collectAsStateWithLifecycle()
    val inDeck = loaded.takeIf { !rec.recording }
    val deckPlaying = inDeck != null && playingId == inDeck.id

    val last = list.firstOrNull()
    val userLabel by Prefs.tapeLabel.collectAsStateWithLifecycle()
    val disc by Prefs.minidisc.collectAsStateWithLifecycle()
    // Long-press the cassette to write on its label: the tape's title with one in, else the deck's own label.
    var writing by remember { mutableStateOf(false) }
    var titling by remember { mutableStateOf<Tape?>(null) }
    if (writing) LabelDialog { writing = false }
    titling?.let { t -> TapeTitleDialog(t) { titling = null } }
    val cassette = @Composable { mod: Modifier ->
        // A titled tape keeps its recording date under the title (the time window shows where it's at).
        val (label, sub) = if (inDeck != null)
            inDeck.label to (inDeck.pretty.takeIf { inDeck.title.isNotBlank() }
                ?: "${if (deckPlaying) "▶" else "❚❚"} ${TapeNames.duration(deckPos)} / ${TapeNames.duration(inDeck.durationMs)}")
        else deckLabel(userLabel, disc, rec.recording, false, last)
        CassetteView(
            label = label, sub = sub,
            spinning = rec.tapeMoving || deckPlaying,
            handwritten = if (inDeck != null) inDeck.title.isNotBlank() else userLabel.isNotBlank(),
            progress = when {
                rec.recording -> (elapsed / 600_000f).coerceAtMost(1f)
                inDeck != null && inDeck.durationMs > 0 -> (deckPos.toFloat() / inDeck.durationMs).coerceIn(0f, 1f)
                else -> 0f
            },
            modifier = mod.combinedClickable(
                onClick = { Feedback.key(); onNav(Screen.LOAD) },
                onLongClick = { Feedback.key(); if (inDeck != null) titling = inDeck else writing = true }
            )
        )
    }
    val tidy = rememberTidySoon(tapes)
    val error = @Composable {
        if (rec.recording) RecStatus(rec)
        rec.error?.let { Text("⚠ $it", color = Deck.orange, fontFamily = Mono, fontSize = 12.sp, maxLines = 2) }
        if (!rec.recording && tidy.isNotEmpty()) {
            val n = tidy.size
            Text(
                pluralStringResource(R.plurals.deck_tidy_warn, n, n, com.dic2phone.Tidy.whenText(tidy.values.min())),
                color = Deck.orange, fontFamily = Mono, fontSize = 11.sp, maxLines = 2,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                modifier = Modifier.clickable { onNav(Screen.TAPES) }
            )
        }
    }

    if (landscape) {
        // Sideways: a proper tape deck. Cassette well on the left, meters on the right, keys along the front.
        Column(
            Modifier
                .fillMaxSize()
                .safeDrawingPadding()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                cassette(Modifier.fillMaxHeight().aspectRatio(DeckArt.CASSETTE_RATIO, matchHeightConstraintsFirst = true))
                Column(
                    Modifier.weight(1f).fillMaxHeight(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    BrandPlate()
                    CounterRow(newCount, rec, elapsed, list.size)
                    Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                        if (inDeck != null) DeckPlayer(
                            inDeck, 44.dp, compact = true, modifier = Modifier.verticalScroll(rememberScrollState())
                        )
                        else VuMeter(if (rec.recording) rec.level else 0f, Modifier.fillMaxWidth(0.9f))
                    }
                    error()
                }
            }
            // With a tape in, its transport keys get their own bank on the front row (no room beside the cassette).
            DeckKeyBank(rec, 64.dp, onNav, needMic, transport = inDeck?.takeIf { !rec.recording }?.let { transportKeys(it) }.orEmpty())
        }
    } else {
        Column(
            Modifier
                .fillMaxSize()
                .safeDrawingPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(if (inDeck != null) 6.dp else 14.dp)
        ) {
            BrandPlate()
            CounterRow(newCount, rec, elapsed, list.size)
            // Slightly smaller with a tape in, to make room for the player (captions, flags, keys).
            cassette(Modifier.fillMaxWidth(if (inDeck != null) 0.82f else 1f))
            // A tape in the deck takes the VU's place (the mic isn't listening then anyway).
            if (inDeck == null) VuMeter(if (rec.recording) rec.level else 0f, Modifier.fillMaxWidth(0.8f))
            error()
            if (inDeck != null) DeckPlayer(inDeck, 52.dp, modifier = Modifier.fillMaxWidth())
            DeckKeyBank(rec, if (inDeck != null) 68.dp else 112.dp, onNav, needMic)
        }
    }
}

/**
 * Text on the deck's tape/disc label: (big line, small line). The user's own writing, if any,
 * stays on the big line; the small line shows what the deck is doing / the last tape.
 */
fun deckLabel(user: String, disc: Boolean, recording: Boolean, playing: Boolean, last: Tape?): Pair<String, String> {
    val stock = if (disc) "MD 74 · SP · STEREO" else "C-60 · TYPE I · NORMAL"
    val lastInfo = last?.let { TapeNames.duration(it.durationMs) + if (it.isNew) " · " + L.s(R.string.badge_new) else "" }
    return if (user.isNotBlank()) user to when {
        recording -> L.s(R.string.deck_lbl_rec_dot)
        playing -> L.s(R.string.deck_lbl_play_dot)
        last != null -> L.s(R.string.deck_lbl_last, last.date, last.time, lastInfo)
        else -> stock
    } else when {
        recording -> L.s(R.string.deck_lbl_rec) to stock
        playing -> L.s(R.string.deck_lbl_play) to stock
        last != null -> "${last.date} ${last.time}" to L.s(R.string.deck_lbl_last_tape, lastInfo)
        else -> "" to stock
    }
}

/** Tape counter (new tapes) on the left; REC lamp, elapsed time and tape count on the right. */
@Composable
private fun CounterRow(newCount: Int, rec: Recorder.State, elapsed: Long, onDeck: Int) {
    val ctx = LocalContext.current
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            TapeCounter(newCount, onReset = { TapeStore.markAllHeard(ctx) })
            Text(stringResource(R.string.deck_new_tapes), color = Deck.dim, fontFamily = Mono, fontSize = 11.sp)
        }
        Spacer(Modifier.weight(1f))
        Column(horizontalAlignment = Alignment.End) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.deck_rec) + " ", color = Deck.dim, fontFamily = Mono, fontSize = 12.sp)
                Led(rec.recording)
            }
            Text(
                TapeNames.duration(elapsed), color = if (rec.recording) Deck.led else Deck.dim,
                fontFamily = Mono, fontSize = 30.sp, fontWeight = FontWeight.Bold
            )
            Text(stringResource(R.string.deck_on_deck, onDeck), color = Deck.dim, fontFamily = Mono, fontSize = 11.sp)
        }
    }
}

/** While recording: locked / noise-activated / tape number / flags, in one line. */
@Composable
private fun RecStatus(rec: Recorder.State) {
    val parts = listOfNotNull(
        stringResource(if (rec.latched) R.string.rec_locked else R.string.rec_holding),
        if (rec.vox) stringResource(if (rec.rolling) R.string.rec_vox_rolling else R.string.rec_vox_waiting) else null,
        if (rec.vox || rec.part > 1) stringResource(R.string.rec_on_tape, TapeNames.duration(rec.tapeMs)) else null,
        if (rec.part > 1) stringResource(R.string.rec_part, rec.part) else null,
        if (rec.flags > 0) "⚑ ${rec.flags}" else null,
    )
    Text(
        parts.joinToString("  ·  "), color = if (rec.vox && !rec.rolling) Deck.dim else Deck.led,
        fontFamily = Mono, fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1
    )
}

/** A press of REC shorter than this is a tap: it locks recording on. */
private const val LATCH_TAP_MS = 350L

/**
 * The deck's piano-key bank: red REC next to the TAPES / SHELF / SETUP keys, labels printed
 * on the faceplate above. REC: hold to record, or tap it to lock recording on (tap again to
 * stop). While recording, a FLAG key marks the moment.
 */
@Composable
private fun DeckKeyBank(
    rec: Recorder.State, keyHeight: Dp, onNav: (Screen) -> Unit, onNeedMic: () -> Unit,
    transport: List<BankKey> = emptyList(),
) {
    val ctx = LocalContext.current
    val p = Deck.palette
    val recording = rec.recording
    val discMode by Prefs.minidisc.collectAsStateWithLifecycle()
    val deckKeys = buildList {
            add(BankKey(
                when {
                    recording && rec.latched -> stringResource(R.string.rec_key_tap_stop)
                    recording -> stringResource(R.string.rec_key_release)
                    else -> stringResource(R.string.rec_key_idle)
                },
                "●", weight = 1.5f,
                labelColor = Deck.red, face1 = p.rec1, face2 = p.rec2, glyphColor = Color.White,
                latched = recording,
                press = { setDown ->
                    // Hand-rolled rather than detectTapGestures: starting to record re-lays out the deck
                    // (a tape's player makes way for the VU, the keys grow), which can slide the key out
                    // from under a resting finger. A tap gesture counts that as a cancel; this just waits
                    // for the finger to lift, wherever the key has gone.
                    pointerInput(Unit) {
                        awaitEachGesture {
                            val down = awaitFirstDown(requireUnconsumed = false)
                            down.consume()
                            suspend fun androidx.compose.ui.input.pointer.AwaitPointerEventScope.lifted() = awaitLift(down.id)
                            if (!hasMic(ctx)) { onNeedMic(); return@awaitEachGesture }
                            if (Recorder.state.value.recording) {
                                // Already recording (locked, or started elsewhere): this press stops it.
                                setDown(true); RecorderService.stop()
                                try { lifted() } finally { setDown(false) }
                                return@awaitEachGesture
                            }
                            setDown(true)
                            val t0 = SystemClock.uptimeMillis()
                            RecorderService.start(ctx, "rec-key")
                            var released = false
                            try { released = lifted() } finally {
                                setDown(false)
                                // Also when the key is torn down mid-press: never leave a hold-to-record running.
                                if (released && SystemClock.uptimeMillis() - t0 < LATCH_TAP_MS) RecorderService.latch()
                                else RecorderService.stop()
                            }
                        }
                    }
                }
            ))
            if (recording) add(BankKey(stringResource(R.string.key_flag) + if (rec.flags > 0) " ${rec.flags}" else "", "⚑", labelColor = Deck.amber) {
                RecorderService.flag()
            })
            add(BankKey(stringResource(R.string.key_tapes), "", icon = if (discMode) KeyIcons.discs else KeyIcons.tapes) { onNav(Screen.TAPES) })
            add(BankKey(stringResource(R.string.key_shelf), "", icon = KeyIcons.shelf) { onNav(Screen.SHELF) })
            add(BankKey(stringResource(R.string.key_setup), "⚙") { onNav(Screen.SETUP) })
    }
    // Sideways with a tape in: two banks on one row, the transport apart from REC / TAPES / SHELF / SETUP.
    // Always the same Row, so the REC bank keeps its place in the tree (and a press in progress)
    // when recording takes the transport away.
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        if (transport.isNotEmpty())
            KeyBank(transport, keyHeight, Modifier.weight(transport.sumOf { it.weight.toDouble() }.toFloat()))
        KeyBank(deckKeys, keyHeight, Modifier.weight(deckKeys.sumOf { it.weight.toDouble() }.toFloat()))
    }
}
