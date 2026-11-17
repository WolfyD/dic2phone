package com.dic2phone.ui

import com.dic2phone.R
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.dic2phone.Captions
import com.dic2phone.Cue
import com.dic2phone.Player
import com.dic2phone.Prefs
import com.dic2phone.Tape
import com.dic2phone.TapeNames
import com.dic2phone.TapeStore
import com.dic2phone.Transcriber
import com.dic2phone.Vault
import com.dic2phone.Whisper
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Captions of a tape (reloaded when tapes change), or null if it has none. */
@Composable
fun rememberCues(t: Tape): List<Cue>? {
    val ctx = LocalContext.current
    val v by TapeStore.version.collectAsStateWithLifecycle()
    val cues by produceState<List<Cue>?>(null, t.id, t.cc, v) {
        value = if (!t.cc) null else withContext(Dispatchers.IO) { Captions.load(ctx.applicationContext, t) }
    }
    return cues
}

private val CAPTION_LINE = 19.sp

/**
 * The caption window's height: room for its three lines, always, so the keys below stay put
 * as captions come and go (a finger holding FF mustn't find the key moved from under it).
 */
@Composable
fun captionHeight(): androidx.compose.ui.unit.Dp =
    with(androidx.compose.ui.platform.LocalDensity.current) { (CAPTION_LINE * 3).toDp() } + 10.dp

/** The caption being spoken right now, subtitle style. */
@Composable
fun CaptionLine(cues: List<Cue>, posMs: Long) {
    val c = Captions.at(cues, posMs)
    Box(
        Modifier.fillMaxWidth().height(captionHeight()).padding(horizontal = 4.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            c?.text ?: "", color = Color(0xFFFFF4C8), fontFamily = Mono, fontWeight = FontWeight.Bold,
            fontSize = 15.sp, lineHeight = CAPTION_LINE, textAlign = TextAlign.Center, maxLines = 3,
            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
            modifier = if (c == null) Modifier else
                Modifier.clip(RoundedCornerShape(4.dp)).background(Color.Black.copy(alpha = .6f)).padding(horizontal = 8.dp, vertical = 4.dp)
        )
    }
}

/** "CAPTIONS · LISTENING 42%" with a cancel key, while captions are being made. */
@Composable
fun CaptionStatusStrip() {
    val s by Transcriber.status.collectAsStateWithLifecycle()
    val err by Transcriber.lastError.collectAsStateWithLifecycle()
    val st = s
    if (st == null) {
        err?.let { e ->
            Text(stringResource(R.string.cc_failed, e), color = Deck.red, fontFamily = Mono, fontSize = 11.sp, maxLines = 2)
        }
        return
    }
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp)).background(Color.Black.copy(alpha = .55f))
            .padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Led(true, size = 10.dp)
        Spacer(Modifier.width(8.dp))
        Column(Modifier.weight(1f)) {
            Text(
                stringResource(R.string.cc_strip, st.index, st.total, st.line, st.pct), color = Deck.led, fontFamily = Mono,
                fontWeight = FontWeight.Bold, fontSize = 12.sp, maxLines = 1
            )
            Box(Modifier.fillMaxWidth().height(3.dp).background(Color.White.copy(alpha = .15f))) {
                Box(Modifier.fillMaxWidth(st.pct / 100f).fillMaxHeight().background(Deck.orange))
            }
        }
        Spacer(Modifier.width(8.dp))
        DeckKey(stringResource(R.string.cancel).uppercase(), Modifier.width(84.dp), height = 34.dp) { Transcriber.cancelAll() }
    }
}

/** Starts captioning, asking for the speech model the first time. */
@Stable
class CaptionStarter internal constructor(private val ctx: Context) {
    private var pending by mutableStateOf<List<Tape>?>(null)

    fun start(tapes: List<Tape>, redo: Boolean = false) {
        if (!Whisper.available) {
            Toast.makeText(ctx, ctx.getString(R.string.cc_need_arm), Toast.LENGTH_LONG).show(); return
        }
        if (tapes.any { it.vault != null } && !Vault.isOpen) {
            Toast.makeText(ctx, ctx.getString(R.string.cc_open_vault), Toast.LENGTH_SHORT).show(); return
        }
        if (Prefs.ccModel.value.isEmpty()) { pending = tapes; return }
        go(tapes, redo)
    }

    private fun go(tapes: List<Tape>, redo: Boolean) {
        Transcriber.enqueue(ctx.applicationContext, tapes)
        val m = Transcriber.Model.byId(Prefs.ccModel.value)
        val fetch = m != null && !Transcriber.installed(ctx, m)
        Toast.makeText(
            ctx,
            when {
                fetch -> ctx.getString(R.string.cc_toast_fetch, m.size)
                redo -> ctx.getString(R.string.cc_toast_redo)
                else -> ctx.resources.getQuantityString(R.plurals.cc_toast_go, tapes.size, tapes.size)
            },
            Toast.LENGTH_SHORT
        ).show()
    }

    @Composable
    fun Dialogs() {
        val p = pending ?: return
        ModelDialog(onDismiss = { pending = null }) { m ->
            Prefs.setCcModel(m.id)
            pending = null
            go(p, false)
        }
    }
}

@Composable
fun rememberCaptionStarter(): CaptionStarter {
    val ctx = LocalContext.current
    return remember(ctx) { CaptionStarter(ctx) }
}

/** First-time choice of speech model (a one-off download). */
@Composable
fun ModelDialog(onDismiss: () -> Unit, onPick: (Transcriber.Model) -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Deck.panel,
        titleContentColor = Deck.text,
        textContentColor = Deck.dim,
        title = { Text(stringResource(R.string.cc_pick_title), fontFamily = Mono, fontWeight = FontWeight.Bold) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    stringResource(R.string.cc_pick_text),
                    fontFamily = Mono, fontSize = 12.sp
                )
                Transcriber.Model.entries.forEach { m ->
                    Column(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp)).border(1.dp, Deck.dim, RoundedCornerShape(6.dp))
                            .clickable { onPick(m) }.padding(10.dp)
                    ) {
                        Text(m.label, color = Deck.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                        Text("${m.size} · " + stringResource(m.note), color = Deck.dim, fontFamily = Mono, fontSize = 11.sp)
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel), color = Deck.text, fontFamily = Mono) } }
    )
}

// ---- Transcript ---------------------------------------------------------------------------

/** The tape's captions as a readable list: tap a line to play from there. */
@Composable
fun TranscriptView(t: Tape, onClose: () -> Unit, onRedo: () -> Unit) {
    val ctx = LocalContext.current
    val cues = rememberCues(t)
    val playing by Player.playingId.collectAsStateWithLifecycle()
    val pos by Player.positionMs.collectAsStateWithLifecycle()
    val isPlaying = playing == t.id
    val current = if (isPlaying && cues != null) cues.indexOf(Captions.at(cues, pos)) else -1
    val list = rememberLazyListState()
    var confirm by remember { mutableStateOf<Confirm?>(null) }
    LaunchedEffect(current) {
        if (current >= 0) {
            val vis = list.layoutInfo.visibleItemsInfo
            if (vis.none { it.index == current } || vis.lastOrNull()?.index == current) list.animateScrollToItem((current - 2).coerceAtLeast(0))
        }
    }

    Column(
        Modifier.fillMaxSize().safeDrawingPadding().padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            DeckKey(stringResource(R.string.back), Modifier.width(96.dp), height = 40.dp) { onClose() }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                SectionTitle(stringResource(R.string.cc_transcript))
                Text(
                    stringResource(R.string.cc_transcript_sub, TapeNames.pretty(t.id)), color = Deck.dim, fontFamily = Mono,
                    fontSize = 11.sp, maxLines = 1
                )
            }
        }

        Box(
            Modifier.weight(1f).fillMaxWidth().clip(RoundedCornerShape(6.dp)).background(Deck.cream)
        ) {
            when {
                cues == null -> Text("…", color = Deck.ink, fontFamily = Mono, modifier = Modifier.padding(12.dp))
                cues.isEmpty() -> Text(
                    stringResource(R.string.cc_no_speech), color = Deck.ink, fontFamily = Mono,
                    modifier = Modifier.padding(12.dp)
                )
                else -> LazyColumn(Modifier.fillMaxSize(), state = list) {
                    itemsIndexed(cues) { i, c ->
                        val now = i == current
                        Row(
                            Modifier.fillMaxWidth()
                                .background(if (now) Deck.orange.copy(alpha = .35f) else Color.Transparent)
                                .clickable { Player.playFrom(ctx, t, c.startMs) }
                                .padding(horizontal = 10.dp, vertical = 5.dp)
                        ) {
                            Text(
                                TapeNames.duration(c.startMs), color = Deck.ink.copy(alpha = .6f), fontFamily = Mono,
                                fontSize = 12.sp, modifier = Modifier.width(58.dp).padding(top = 2.dp)
                            )
                            Text(
                                c.text, color = Deck.ink, fontFamily = Mono, fontSize = 14.sp,
                                fontWeight = if (now) FontWeight.Bold else FontWeight.Normal,
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                }
            }
        }

        if (isPlaying) KeyRow {
            DeckKey(stringResource(R.string.stop) + "  " + TapeNames.duration(pos), Modifier.weight(1f)) { Player.stop() }
        }
        KeyRow {
            DeckKey(stringResource(R.string.cc_copy), Modifier.weight(1f), enabled = !cues.isNullOrEmpty()) {
                val cm = ctx.getSystemService(ClipboardManager::class.java)
                cm.setPrimaryClip(ClipData.newPlainText("Transcript", Captions.transcript(t, cues!!)))
                Toast.makeText(ctx, ctx.getString(R.string.cc_copied), Toast.LENGTH_SHORT).show()
            }
            DeckKey(stringResource(R.string.cc_share), Modifier.weight(1f), enabled = !cues.isNullOrEmpty()) { shareText(ctx, t, cues!!) }
            DeckKey(".SRT", Modifier.weight(1f), enabled = !cues.isNullOrEmpty()) { shareSrt(ctx, t, cues!!) }
            DeckKey(stringResource(R.string.cc_redo), Modifier.weight(1f)) {
                confirm = Confirm(
                    ctx.getString(R.string.cc_redo_title),
                    ctx.getString(R.string.cc_redo_text),
                    ctx.getString(R.string.cc_redo)
                ) { onRedo() }
            }
        }
    }
    confirm?.let { c -> ConfirmDialog(c) { confirm = null } }
}

private fun shareText(ctx: Context, t: Tape, cues: List<Cue>) {
    val send = Intent(Intent.ACTION_SEND)
        .setType("text/plain")
        .putExtra(Intent.EXTRA_SUBJECT, ctx.getString(R.string.cc_share_subject, TapeNames.pretty(t.id)))
        .putExtra(Intent.EXTRA_TEXT, Captions.transcript(t, cues))
    ctx.startActivity(Intent.createChooser(send, ctx.getString(R.string.cc_share_chooser)))
}

private fun shareSrt(ctx: Context, t: Tape, cues: List<Cue>) {
    val dir = File(ctx.cacheDir, "cc").apply { mkdirs() }
    val f = File(dir, t.id.substringBeforeLast('.') + ".srt")
    f.writeText(Captions.toSrt(cues))
    val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.files", f)
    val send = Intent(Intent.ACTION_SEND)
        .setType("application/x-subrip")
        .putExtra(Intent.EXTRA_STREAM, uri)
        .putExtra(Intent.EXTRA_SUBJECT, ctx.getString(R.string.cc_srt_subject, TapeNames.pretty(t.id)))
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    send.clipData = ClipData.newRawUri("", uri)
    ctx.startActivity(Intent.createChooser(send, ctx.getString(R.string.cc_srt_chooser)))
}

// ---- Search -------------------------------------------------------------------------------

/** Finds words across every captioned tape (vault included while it's open). */
@Composable
fun SearchScreen(onBack: () -> Unit) {
    val ctx = LocalContext.current
    val v by TapeStore.version.collectAsStateWithLifecycle()
    val vaultOpen by Vault.open.collectAsStateWithLifecycle()
    val index by produceState<List<Pair<Tape, List<Cue>>>?>(null, v, vaultOpen) {
        value = withContext(Dispatchers.IO) {
            val app = ctx.applicationContext
            (TapeStore.deck(app) + TapeStore.shelf(app) + Vault.list(app))
                .filter { it.cc }
                .mapNotNull { t -> Captions.load(app, t)?.let { t to it } }
        }
    }
    var query by remember { mutableStateOf("") }
    val hits = remember(index, query) { index?.let { Captions.search(it, query) }.orEmpty() }
    val playing by Player.playingId.collectAsStateWithLifecycle()
    val pos by Player.positionMs.collectAsStateWithLifecycle()
    DisposableEffect(Unit) {
        onDispose { if ((ctx as? Activity)?.isChangingConfigurations != true) Player.stop() }
    }

    Column(
        Modifier.fillMaxSize().safeDrawingPadding().padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            DeckKey(stringResource(R.string.back), Modifier.width(96.dp), height = 40.dp) { onBack() }
            Spacer(Modifier.width(12.dp))
            Column {
                SectionTitle(stringResource(R.string.search_title))
                Text(
                    index?.let { pluralStringResource(R.plurals.search_count, it.size, it.size) + if (!vaultOpen && Vault.exists(ctx)) " · " + stringResource(R.string.search_vault_locked) else "" }
                        ?: stringResource(R.string.search_reading),
                    color = Deck.dim, fontFamily = Mono, fontSize = 11.sp, maxLines = 1
                )
            }
        }
        OutlinedTextField(
            query, { query = it },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text(stringResource(R.string.search_hint), fontFamily = Mono, color = Deck.dim) },
            textStyle = androidx.compose.ui.text.TextStyle(fontFamily = Mono, color = Deck.text, fontSize = 16.sp),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = Deck.amber, unfocusedBorderColor = Deck.dim, cursorColor = Deck.amber
            ),
        )

        Box(Modifier.weight(1f).fillMaxWidth()) {
            when {
                index?.isEmpty() == true -> Hint(stringResource(R.string.search_none))
                query.isBlank() -> Hint(stringResource(R.string.search_type))
                hits.isEmpty() && index != null -> Hint(stringResource(R.string.search_not_found))
                else -> LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    items(hits) { h ->
                        val now = playing == h.tape.id && pos in h.cue.startMs..(h.cue.endMs + 1500)
                        Column(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp))
                                .background(if (now) Deck.orange.copy(alpha = .35f) else Deck.cream)
                                .clickable { Player.playFrom(ctx, h.tape, (h.cue.startMs - 300).coerceAtLeast(0)) }
                                .padding(horizontal = 10.dp, vertical = 6.dp)
                        ) {
                            Text(
                                (if (h.tape.vault != null) "🔒 " else "") + TapeNames.pretty(h.tape.id) +
                                    "  ▶ " + TapeNames.duration(h.cue.startMs),
                                color = Deck.ink.copy(alpha = .65f), fontFamily = Mono, fontSize = 11.sp
                            )
                            Text(
                                buildAnnotatedString {
                                    val s = h.cue.text
                                    append(s.substring(0, h.start))
                                    withStyle(SpanStyle(fontWeight = FontWeight.Bold, background = Deck.amber.copy(alpha = .55f))) {
                                        append(s.substring(h.start, h.end))
                                    }
                                    append(s.substring(h.end))
                                },
                                color = Deck.ink, fontFamily = Mono, fontSize = 14.sp
                            )
                        }
                    }
                }
            }
        }

        val t = index?.firstOrNull { it.first.id == playing }
        if (t != null) {
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(Color.Black.copy(alpha = .55f)).padding(6.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                CaptionLine(t.second, pos)
                DeckKey(stringResource(R.string.stop) + "  " + TapeNames.duration(pos), Modifier.fillMaxWidth(), height = 44.dp) { Player.stop() }
            }
        }
    }
}

@Composable
private fun Hint(text: String) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(text, color = Deck.dim, fontFamily = Mono, fontSize = 14.sp, textAlign = TextAlign.Center)
    }
}
