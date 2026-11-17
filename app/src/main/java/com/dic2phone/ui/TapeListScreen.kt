package com.dic2phone.ui

import com.dic2phone.R
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import android.app.Activity
import android.content.Intent
import android.provider.Settings
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.interaction.collectIsPressedAsState
import com.dic2phone.Feedback
import com.dic2phone.TapeSort
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.dic2phone.LoFi
import com.dic2phone.MetaStore
import com.dic2phone.Player
import com.dic2phone.Prefs
import com.dic2phone.Tape
import com.dic2phone.TapeNames
import com.dic2phone.TapeStore
import com.dic2phone.Transcriber
import com.dic2phone.Vault
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal class Confirm(val title: String, val text: String, val yes: String, val action: () -> Unit)

/** Deck tapes auto-tidy deletes soon (id → when), worked out off the main thread. */
@Composable
internal fun rememberTidySoon(deck: List<Tape>?): Map<String, Long> {
    val ctx = LocalContext.current
    val days by Prefs.tidyDays.collectAsStateWithLifecycle()
    val loadedId by Player.loaded.collectAsStateWithLifecycle()
    val state = androidx.compose.runtime.produceState(emptyMap<String, Long>(), deck, days, loadedId?.id) {
        value = if (deck == null || days <= 0) emptyMap()
        else withContext(Dispatchers.IO) { runCatching { com.dic2phone.Tidy.soon(ctx.applicationContext, deck) }.getOrDefault(emptyMap()) }
    }
    return state.value
}

/** Small orange "GOES TOMORROW" tag for a tape auto-tidy will delete. */
@Composable
internal fun TidyBadge(at: Long?) {
    if (at == null) return
    Text(
        "✂ ${com.dic2phone.Tidy.whenText(at)}", color = Color.White, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 10.sp,
        modifier = Modifier.clip(RoundedCornerShape(3.dp)).background(Deck.orange).padding(horizontal = 4.dp, vertical = 2.dp)
    )
    Spacer(Modifier.width(6.dp))
}

/** Why the vault door won't open, if it won't. */
private enum class DoorProblem { NO_SCREEN_LOCK, LOST }

/** The deck's tape list, the long-term shelf, or the locked vault inside the shelf. */
@Composable
fun TapeListScreen(kind: Shelf, onBack: () -> Unit, onNav: (Screen) -> Unit, loadMode: Boolean = false) {
    val ctx = LocalContext.current
    val activity = ctx as? Activity
    val scope = rememberCoroutineScope()
    val loaded by rememberTapes(kind)
    val vaultOpen by Vault.open.collectAsStateWithLifecycle()
    val locked = kind == Shelf.VAULT && !vaultOpen
    val sortKey = kind.name.lowercase()
    val sorts by Prefs.sorts.collectAsStateWithLifecycle()
    val sort = sorts[sortKey] ?: TapeSort.NEWEST
    val tapes = if (locked) emptyList() else remember(loaded, sort) { sort.apply(loaded.orEmpty()) }
    val inDeck by Player.loaded.collectAsStateWithLifecycle()
    val playing by Player.playingId.collectAsStateWithLifecycle()
    val progress by Player.progress.collectAsStateWithLifecycle()
    val queued by Transcriber.queued.collectAsStateWithLifecycle()
    var selected by remember(kind) { mutableStateOf(emptySet<String>()) }
    var confirm by remember { mutableStateOf<Confirm?>(null) }
    var reading by remember { mutableStateOf<String?>(null) }   // tape id whose transcript is open
    var info by remember { mutableStateOf<String?>(null) }      // tape id whose INFO is open
    var problem by remember { mutableStateOf<DoorProblem?>(null) }
    val captions = rememberCaptionStarter()
    val sel = tapes.filter { it.id in selected }
    val tidy = rememberTidySoon(if (kind == Shelf.DECK) loaded else null)
    val disc by Prefs.minidisc.collectAsStateWithLifecycle()

    // Back first closes the transcript, then stops the tape (these handlers are composed after
    // MainActivity's, so they win); only then does back leave. Leaving the list any other way
    // stops the tape too. Rotation recreates the activity, so that must not count as leaving.
    BackHandler(playing != null && reading == null) { Player.stop() }
    BackHandler(reading != null) { reading = null }
    DisposableEffect(Unit) {
        onDispose { if (activity?.isChangingConfigurations != true) Player.stop() }
    }

    fun toast(s: String) = Toast.makeText(ctx, s, Toast.LENGTH_SHORT).show()

    /** Opens the vault (fingerprint / screen lock), then runs [then]. */
    fun openVault(then: () -> Unit = {}) {
        val a = activity ?: return
        Vault.unlock(a) { r ->
            when (r) {
                Vault.Unlock.Ok -> { problem = null; then() }
                Vault.Unlock.Cancelled -> {}
                Vault.Unlock.NoScreenLock -> { problem = DoorProblem.NO_SCREEN_LOCK; if (kind != Shelf.VAULT) onNav(Screen.VAULT) }
                Vault.Unlock.Lost -> { problem = DoorProblem.LOST; if (kind != Shelf.VAULT) onNav(Screen.VAULT) }
                is Vault.Unlock.Failed -> Toast.makeText(ctx, ctx.getString(R.string.list_vault_err, r.msg), Toast.LENGTH_LONG).show()
            }
        }
    }

    fun share(list: List<Tape>) {
        if (kind == Shelf.VAULT) {
            scope.launch {
                val files = withContext(Dispatchers.IO) { Vault.exportForSending(ctx.applicationContext, list) }
                if (files.isNotEmpty()) TapeStore.shareIntent(ctx, list, files)?.let { ctx.startActivity(it) }
                else toast(ctx.getString(R.string.list_unseal_fail))
                selected = emptySet()
            }
            return
        }
        TapeStore.shareIntent(ctx, list)?.let { ctx.startActivity(it) }
        selected = emptySet()
    }

    var dubbing by remember { mutableStateOf<String?>(null) }
    /** Tapes waiting for the "how to send" choice. */
    var sending by remember { mutableStateOf<List<Tape>?>(null) }

    /** SEND: vault tapes go as they are; others ask whether to bake the tape sound in. */
    fun send(list: List<Tape>) { if (kind == Shelf.VAULT) share(list) else sending = list }

    /** Into the deck with a clunk, and back to the deck. */
    fun putInDeck(t: Tape) {
        Feedback.doorClose(ctx)
        Player.load(t)
        selected = emptySet()
        onNav(Screen.DECK)
    }

    /** Bake the tape effects into copies, then share those. Originals stay clean. */
    fun sendLoFi(list: List<Tape>) {
        val fx = Prefs.fx.value
        if (!fx.any) {
            Toast.makeText(ctx, ctx.getString(R.string.list_fx_off), Toast.LENGTH_LONG).show()
            return
        }
        scope.launch {
            val files = mutableListOf<File>()
            list.forEachIndexed { i, t ->
                dubbing = ctx.getString(R.string.list_dubbing, i + 1, list.size)
                // Shared with the deck / idle renders, so the same copy is never written twice at once.
                val f = LoFi.warm(ctx, t, fx).await()
                withContext(Dispatchers.IO) {
                    f?.also { MetaStore.tagCopy(it, t.id, MetaStore.load(ctx, t)) }
                }?.let { files += it }
            }
            dubbing = null
            if (files.size < list.size) toast(ctx.getString(R.string.list_dub_fail, list.size - files.size))
            if (files.isNotEmpty()) TapeStore.shareIntent(ctx, list, files)?.let { ctx.startActivity(it) }
            selected = emptySet()
        }
    }

    fun io(msg: String? = null, block: () -> Unit) {
        scope.launch {
            withContext(Dispatchers.IO) { block() }
            selected = emptySet()
            msg?.let { toast(it) }
        }
    }

    /** Seal tapes into the vault, opening it first if needed. */
    fun lockAway(list: List<Tape>) {
        val app = ctx.applicationContext
        openVault {
            busyIo(scope, { dubbing = it }, ctx.getString(R.string.list_locking, list.size)) {
                val r = Vault.lockAway(app, list)
                withContext(Dispatchers.Main) {
                    selected = emptySet()
                    when {
                        r.locked < list.size -> toast(ctx.getString(R.string.list_locked_some, r.locked, list.size))
                        r.leftBehind > 0 -> Toast.makeText(
                            ctx, ctx.getString(R.string.list_left_behind, r.leftBehind),
                            Toast.LENGTH_LONG
                        ).show()
                        else -> toast(ctx.getString(R.string.list_locked_ok))
                    }
                }
            }
        }
    }

    /** TEXT on a single transcribed tape opens its transcript; otherwise transcribes. */
    fun ccOrText(list: List<Tape>) {
        val one = list.singleOrNull()
        if (one != null && one.cc) { reading = one.id; selected = emptySet(); return }
        val need = list.filter { !it.cc && it.id !in queued }
        if (need.isEmpty()) { toast(ctx.getString(R.string.list_already_cc)); return }
        captions.start(need)
        selected = emptySet()
    }

    reading?.let { id ->
        val t = tapes.firstOrNull { it.id == id }
        if (t == null) reading = null
        else {
            TranscriptView(t, onClose = { reading = null }, onRedo = { captions.start(listOf(t), redo = true); reading = null })
            captions.Dialogs()
            return
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .safeDrawingPadding()
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            DeckKey(stringResource(if (kind == Shelf.VAULT) R.string.back_shelf else R.string.back_deck), Modifier.width(96.dp), height = 40.dp) { onBack() }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                SectionTitle(
                    when (kind) {
                        Shelf.DECK -> stringResource(if (loadMode) R.string.list_title_load else R.string.list_title_deck)
                        Shelf.SHELF -> stringResource(R.string.list_title_shelf)
                        Shelf.VAULT -> stringResource(R.string.vault)
                    }
                )
                Text(
                    when (kind) {
                        Shelf.DECK -> stringResource(
                            R.string.list_sub_deck, pluralStringResource(R.plurals.n_tapes, tapes.size, tapes.size), tapes.count { it.isNew }
                        ) + if (tidy.isNotEmpty()) " · " + stringResource(R.string.list_sub_tidy, tidy.size) else ""
                        Shelf.SHELF -> stringResource(R.string.list_sub_shelf, tapes.size, TapeStore.shelfRelPath)
                        Shelf.VAULT -> if (locked) stringResource(R.string.list_sub_vault_locked) else stringResource(R.string.list_sub_vault_open, tapes.size)
                    },
                    color = Deck.dim, fontFamily = Mono, fontSize = 11.sp, maxLines = 1
                )
            }
            Spacer(Modifier.width(8.dp))
            DeckKey("⌕", Modifier.width(48.dp), height = 40.dp) { onNav(Screen.SEARCH) }
        }

        if (!locked && tapes.isNotEmpty()) Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                when {
                    loadMode -> stringResource(if (disc) R.string.list_hint_load_disc else R.string.list_hint_load)
                    else -> stringResource(if (disc) R.string.list_hint_disc else R.string.list_hint)
                },
                color = if (loadMode) Deck.amber else Deck.dim, fontFamily = Mono, fontSize = 11.sp,
                fontWeight = if (loadMode) FontWeight.Bold else null, maxLines = 1, modifier = Modifier.weight(1f)
            )
            if (tapes.size > 1) DeckKey("↕ ${sortName(sort)}", Modifier.width(104.dp), height = 32.dp) {
                Prefs.setSort(sortKey, sort.next())
            }
        }

        val listMod = Modifier.weight(1f).fillMaxWidth()
        if (locked) {
            VaultDoor(problem, listMod, onUnlock = { openVault() }, onReset = {
                confirm = Confirm(
                    ctx.getString(R.string.list_reset_title),
                    ctx.getString(R.string.list_reset_text),
                    ctx.getString(R.string.list_reset)
                ) { io(ctx.getString(R.string.list_reset_done)) { Vault.reset(ctx.applicationContext) }; problem = null }
            })
        } else if (loaded != null && tapes.isEmpty()) {
            Box(listMod, contentAlignment = Alignment.Center) {
                Text(
                    when (kind) {
                        Shelf.DECK -> stringResource(R.string.list_empty_deck)
                        Shelf.SHELF -> stringResource(R.string.list_empty_shelf)
                        Shelf.VAULT -> stringResource(R.string.list_empty_vault)
                    },
                    color = Deck.dim, fontFamily = Mono, fontSize = 14.sp
                )
            }
        } else if (disc) {
            DiscStack(
                tapes, selected, playing, progress, queued, tidy, inDeck?.id, loadMode && kind == Shelf.DECK,
                frame = when (kind) { Shelf.DECK -> DiscFrame.CASE; Shelf.SHELF -> DiscFrame.WOOD; Shelf.VAULT -> DiscFrame.STEEL },
                modifier = listMod,
                onTap = { t ->
                    when {
                        selected.isNotEmpty() -> selected = selected.toggle(t.id)
                        loadMode && kind == Shelf.DECK -> putInDeck(t)
                        else -> Player.toggle(ctx, t)
                    }
                },
                onLong = { t -> selected = selected.toggle(t.id) },
                onLoad = { t -> putInDeck(t) },
            )
        } else if (kind == Shelf.DECK) {
            CarryCase(listMod) {
                items(tapes, key = { it.id }) { t ->
                    TapeCaseRow(
                        t, t.id in selected, playing == t.id, if (playing == t.id) progress else 0f, t.id in queued, tidy[t.id],
                        loadMode = loadMode, inDeck = inDeck?.id == t.id,
                        onTap = {
                            when {
                                selected.isNotEmpty() -> selected = selected.toggle(t.id)
                                loadMode -> putInDeck(t)
                                else -> Player.toggle(ctx, t)
                            }
                        },
                        onLong = { selected = selected.toggle(t.id) },
                        onLoad = { putInDeck(t) },
                    )
                }
            }
        } else {
            ShelfRack(tapes, selected, playing, progress, queued, steel = kind == Shelf.VAULT, modifier = listMod,
                inDeck = inDeck?.id,
                onTap = { t -> if (selected.isNotEmpty()) selected = selected.toggle(t.id) else Player.toggle(ctx, t) },
                onLong = { t -> selected = selected.toggle(t.id) },
                onLoad = { t -> putInDeck(t) })
        }

        // The tape that's playing, in the deck window with its reels turning, captions below.
        tapes.firstOrNull { it.id == playing }?.let { t ->
            NowPlaying(t, progress) { reading = t.id }
        }

        CaptionStatusStrip()

        if (kind == Shelf.SHELF) VaultBar { onNav(Screen.VAULT) }

        // Action keys
        if (dubbing != null) {
            KeyRow {
                Box(Modifier.weight(1f).height(52.dp), contentAlignment = Alignment.Center) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Led(true, size = 12.dp)
                        Text(
                            "  ${dubbing.orEmpty()}", color = Deck.led, fontFamily = Mono,
                            fontWeight = FontWeight.Bold, fontSize = 14.sp
                        )
                    }
                }
            }
        } else if (sel.isNotEmpty()) {
            sel.singleOrNull()?.let { one ->
                KeyRow {
                    DeckKey(stringResource(R.string.list_put_in), Modifier.weight(2f)) { putInDeck(one) }
                    DeckKey(stringResource(R.string.info), Modifier.weight(1f)) { info = one.id }
                }
            }
            KeyRow {
                DeckKey(stringResource(R.string.list_send_n, sel.size), Modifier.weight(1f)) { send(sel) }
                DeckKey(stringResource(R.string.list_text), Modifier.weight(1f)) { ccOrText(sel) }
                DeckKey("✕", Modifier.width(52.dp)) { selected = emptySet() }
            }
            KeyRow {
                when (kind) {
                    Shelf.DECK -> {
                        DeckKey(stringResource(R.string.list_shelve), Modifier.weight(1f)) { io(ctx.getString(R.string.list_shelved)) { TapeStore.shelve(ctx, sel) } }
                        DeckKey(stringResource(R.string.list_lock), Modifier.weight(1f)) { lockAway(sel) }
                    }
                    Shelf.SHELF -> DeckKey(stringResource(R.string.list_lock), Modifier.weight(1f)) { lockAway(sel) }
                    Shelf.VAULT -> DeckKey(stringResource(R.string.list_take_out_key), Modifier.weight(1f)) {
                        confirm = Confirm(
                            ctx.getString(R.string.list_take_out_title, sel.size),
                            ctx.getString(R.string.list_take_out_text),
                            ctx.getString(R.string.list_take_out_key)
                        ) {
                            val app = ctx.applicationContext
                            io { val n = Vault.takeOut(app, sel); if (n < sel.size) scope.launch { toast(ctx.getString(R.string.list_took_some, n, sel.size)) } }
                        }
                    }
                }
                DeckKey(stringResource(R.string.list_erase), Modifier.weight(1f), textColor = Deck.red) {
                    confirm = Confirm(ctx.getString(R.string.list_erase_title, sel.size), ctx.getString(R.string.list_erase_text), ctx.getString(R.string.list_erase)) {
                        io { TapeStore.delete(ctx, sel) }
                    }
                }
            }
        } else if (!locked) {
            KeyRow {
                DeckKey(stringResource(R.string.list_send_all), Modifier.weight(1f), enabled = tapes.isNotEmpty()) { send(tapes) }
                DeckKey(stringResource(R.string.list_select_all), Modifier.weight(1f), enabled = tapes.isNotEmpty()) {
                    selected = tapes.map { it.id }.toSet()
                }
                when (kind) {
                    Shelf.DECK -> DeckKey(stringResource(R.string.list_erase_all), Modifier.weight(1f), enabled = tapes.isNotEmpty(), textColor = Deck.red) {
                        confirm = Confirm(
                            ctx.getString(R.string.list_wipe_title),
                            ctx.getString(R.string.list_wipe_text, tapes.size),
                            ctx.getString(R.string.list_erase_all)
                        ) { io { TapeStore.wipeDeck(ctx) } }
                    }
                    Shelf.VAULT -> DeckKey(stringResource(R.string.list_lock), Modifier.weight(1f)) { Vault.lock() }
                    Shelf.SHELF -> {}
                }
            }
        }
    }

    captions.Dialogs()
    confirm?.let { c -> ConfirmDialog(c) { confirm = null } }
    sending?.let { list ->
        SendDialog(
            list.size,
            onPlain = { share(list) },
            onTapeSound = { sendLoFi(list) },
            onSetup = { selected = emptySet(); onNav(Screen.SETUP) },
            onDismiss = { sending = null },
        )
    }
    info?.let { id ->
        val t = tapes.firstOrNull { it.id == id }
        if (t == null) info = null else MetaDialog(t) { info = null; selected = emptySet() }
    }
}

/** Runs [block] on IO while the action-key row shows [label]. */
private fun busyIo(
    scope: kotlinx.coroutines.CoroutineScope, show: (String?) -> Unit, label: String, block: suspend () -> Unit,
) {
    scope.launch {
        show(label)
        try { withContext(Dispatchers.IO) { block() } } finally { show(null) }
    }
}

@Composable
internal fun ConfirmDialog(c: Confirm, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Deck.panel,
        titleContentColor = Deck.text,
        textContentColor = Deck.dim,
        title = { Text(c.title, fontFamily = Mono, fontWeight = FontWeight.Bold) },
        text = { Text(c.text, fontFamily = Mono) },
        confirmButton = {
            TextButton(onClick = { onDismiss(); c.action() }) {
                Text(c.yes, color = Deck.red, fontFamily = Mono, fontWeight = FontWeight.Bold)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel), color = Deck.text, fontFamily = Mono) }
        }
    )
}

private fun Set<String>.toggle(id: String) = if (id in this) this - id else this + id

/** The playing tape in the deck window, the current caption under it. */
@Composable
private fun NowPlaying(t: Tape, progress: Float, onText: () -> Unit) {
    val cues = rememberCues(t)
    val pos by Player.positionMs.collectAsStateWithLifecycle()
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(Color.Black.copy(alpha = .55f))
            .padding(6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            CassetteView(
                label = t.label, handwritten = t.title.isNotBlank(),
                sub = stringResource(R.string.list_playing, TapeNames.duration((t.durationMs * progress).toLong()), TapeNames.duration(t.durationMs)),
                spinning = true, progress = progress,
                modifier = Modifier.height(96.dp)
            )
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                DeckKey(stringResource(R.string.stop), Modifier.fillMaxWidth(), height = if (cues != null) 45.dp else 64.dp) { Player.stop() }
                if (cues != null) DeckKey(stringResource(R.string.list_text), Modifier.fillMaxWidth(), height = 45.dp) { onText() }
            }
        }
        if (cues != null) CaptionLine(cues, pos)
    }
}

@Composable
private fun sortName(s: TapeSort) = stringResource(
    when (s) {
        TapeSort.NEWEST -> R.string.sort_newest
        TapeSort.OLDEST -> R.string.sort_oldest
        TapeSort.LONGEST -> R.string.sort_longest
        TapeSort.TITLE -> R.string.sort_title
    }
)

/** The black plastic carry case the deck's tapes stand in, spines out. */
@Composable
private fun CarryCase(modifier: Modifier, content: androidx.compose.foundation.lazy.LazyListScope.() -> Unit) {
    val shape = RoundedCornerShape(8.dp)
    LazyColumn(
        modifier
            .shadow(4.dp, shape)
            .clip(shape)
            .background(Brush.verticalGradient(listOf(Color(0xFF1A1A1C), Color(0xFF0A0A0B))))
            .border(2.dp, Color(0xFF2C2C30), shape)
            .padding(horizontal = 6.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 6.dp),
        content = content
    )
}

/**
 * A deck tape as a cassette case seen edge-on: smoky clear plastic with the J-card's spine
 * showing through, and a little ⏏ key on the end that puts it straight into the deck.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun TapeCaseRow(
    t: Tape, selected: Boolean, playing: Boolean, progress: Float, queued: Boolean, tidyAt: Long?,
    loadMode: Boolean, inDeck: Boolean,
    onTap: () -> Unit, onLong: () -> Unit, onLoad: () -> Unit,
) {
    val shape = RoundedCornerShape(3.dp)
    Row(
        Modifier
            .fillMaxWidth()
            .height(58.dp)
            .clip(shape)
            .background(Brush.verticalGradient(listOf(Color(0xFF45454B), Color(0xFF232327), Color(0xFF111113))))
            .border(if (selected) 2.5.dp else 1.dp, if (selected) Deck.red else Color.Black, shape)
            .drawWithContent {
                drawContent()
                // the clear case's gloss: a bright top edge fading down over the label
                drawRect(Color.White.copy(alpha = .28f), size = Size(size.width, 1.dp.toPx()))
                drawRect(
                    Brush.verticalGradient(listOf(Color.White.copy(alpha = .13f), Color.Transparent), endY = size.height * .5f),
                    size = Size(size.width, size.height * .5f)
                )
            }
            .padding(start = 5.dp, top = 5.dp, bottom = 5.dp, end = if (loadMode) 5.dp else 0.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // J-card spine
        Row(
            Modifier
                .weight(1f)
                .fillMaxHeight()
                .clip(RoundedCornerShape(1.dp))
                .background(Deck.cream)
                .combinedClickable(onClick = onTap, onLongClick = onLong),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(Modifier.width(16.dp).fillMaxHeight()) {
                Deck.stripes.forEach { Box(Modifier.weight(1f).fillMaxHeight().background(it)) }
            }
            Text(
                when { selected -> "✔"; loadMode -> "⏏"; playing -> "■"; else -> "▶" },
                color = if (selected) Deck.red else Deck.ink, fontSize = 16.sp, fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center, modifier = Modifier.width(28.dp)
            )
            Column(Modifier.weight(1f)) {
                TitleText(t.title, t.date, Deck.ink, 15f)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        if (t.title.isNotBlank()) "${t.date} ${t.time}" else t.time,
                        color = Deck.ink.copy(alpha = .75f), fontFamily = Mono, fontSize = 12.sp, maxLines = 1
                    )
                    if (playing) {
                        Spacer(Modifier.width(8.dp))
                        Box(Modifier.weight(1f).height(4.dp).background(Deck.ink.copy(alpha = .15f))) {
                            Box(Modifier.fillMaxWidth(progress).fillMaxHeight().background(Deck.orange))
                        }
                        Spacer(Modifier.width(8.dp))
                    }
                }
            }
            if (inDeck) { Badge(stringResource(R.string.badge_in_deck), Deck.cream, Deck.ink); Spacer(Modifier.width(6.dp)) }
            if (t.isNew) { Badge(stringResource(R.string.badge_new), Color.White, Deck.red); Spacer(Modifier.width(6.dp)) }
            TidyBadge(tidyAt)
            CcBadge(t.cc, queued, Deck.ink)
            Text(
                TapeNames.duration(t.durationMs), color = Deck.ink, fontFamily = Mono,
                fontWeight = FontWeight.Bold, fontSize = 14.sp
            )
            Spacer(Modifier.width(10.dp))
        }
        if (!loadMode) LoadKey(enabled = !inDeck, onClick = onLoad)
    }
}

/** The little ⏏ key on the end of a case: straight into the deck. */
@Composable
internal fun LoadKey(enabled: Boolean, onClick: () -> Unit) {
    val src = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
    val pressed by src.collectIsPressedAsState()
    val a11y = stringResource(R.string.list_put_in_a11y)
    Box(
        Modifier
            .width(46.dp)
            .fillMaxHeight()
            .semantics { contentDescription = a11y }
            .clickable(interactionSource = src, indication = null, enabled = enabled, role = Role.Button) { onClick() },
        contentAlignment = Alignment.Center
    ) {
        PianoKey(animateKeyDown(pressed), 40.dp, Modifier.width(34.dp).alpha(if (enabled) 1f else .35f)) {
            Text("⏏", color = Deck.keyText, fontSize = 15.sp, fontWeight = FontWeight.Black)
        }
    }
}

@Composable
internal fun Badge(text: String, fg: Color, bg: Color) {
    Text(
        text, color = fg, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 11.sp,
        modifier = Modifier.clip(RoundedCornerShape(3.dp)).background(bg).padding(horizontal = 5.dp, vertical = 2.dp)
    )
}

/** "TXT" box when a tape has a transcript, "TXT…" while it's being made. */
@Composable
internal fun CcBadge(cc: Boolean, queued: Boolean, ink: Color) {
    if (!cc && !queued) return
    Text(
        stringResource(R.string.badge_txt) + if (queued) "…" else "", color = if (queued) Deck.orange else ink, fontFamily = Mono,
        fontWeight = FontWeight.Bold, fontSize = 10.sp,
        modifier = Modifier
            .border(1.5.dp, if (queued) Deck.orange else ink, RoundedCornerShape(3.dp))
            .padding(horizontal = 4.dp, vertical = 1.dp)
    )
    Spacer(Modifier.width(8.dp))
}

/** The shelf: a wooden rack holding tapes as cassette-case spines. The vault is the steel one. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ShelfRack(
    tapes: List<Tape>, selected: Set<String>, playing: String?, progress: Float, queued: Set<String>,
    steel: Boolean, modifier: Modifier, inDeck: String?,
    onTap: (Tape) -> Unit, onLong: (Tape) -> Unit, onLoad: (Tape) -> Unit,
) {
    val side = if (steel) Brush.horizontalGradient(listOf(Color(0xFF5E646B), Color(0xFFB4BAC0), Color(0xFF5E646B)))
    else Brush.horizontalGradient(listOf(Color(0xFF5A3A22), Color(0xFF7A5232), Color(0xFF5A3A22)))
    val back = if (steel) Color(0xFF1B1E22) else Color(0xFF24170D)
    Row(modifier.clip(RoundedCornerShape(6.dp)).background(if (steel) Color(0xFF3A3F45) else Color(0xFF3E2716))) {
        Box(Modifier.width(12.dp).fillMaxHeight().background(side))
        LazyColumn(
            Modifier.weight(1f).fillMaxHeight().background(back).padding(horizontal = 6.dp),
        ) {
            items(tapes, key = { it.id }) { t ->
                val isSel = t.id in selected
                val isPlay = playing == t.id
                Column {
                    Spacer(Modifier.height(4.dp))
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .height(48.dp)
                            .clip(RoundedCornerShape(2.dp))
                            .background(Brush.verticalGradient(listOf(Color(0xFF3B3B40), Color(0xFF151517))))
                            .border(if (isSel) 2.dp else 0.dp, if (isSel) Deck.red else Color.Transparent, RoundedCornerShape(2.dp))
                            .padding(start = 6.dp, top = 5.dp, bottom = 5.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(
                            Modifier.weight(1f).fillMaxHeight()
                                .combinedClickable(onClick = { onTap(t) }, onLongClick = { onLong(t) }),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                        Row(Modifier.fillMaxHeight().width(22.dp)) {
                            Deck.stripes.forEach { Box(Modifier.weight(1f).fillMaxHeight().background(it)) }
                        }
                        Row(
                            Modifier.weight(1f).fillMaxHeight().background(Deck.cream).padding(horizontal = 8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                if (isSel) "✔ " else if (isPlay) "■ " else "",
                                color = Deck.red, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 13.sp
                            )
                            if (t.title.isBlank()) TitleText(t.title, "${t.date}  ${t.time}", Deck.ink, 13f, Modifier.weight(1f))
                            else Column(Modifier.weight(1f)) {
                                TitleText(t.title, "", Deck.ink, 12f)
                                Text("${t.date}  ${t.time}", color = Deck.ink.copy(alpha = .7f), fontFamily = Mono, fontSize = 10.sp, lineHeight = 11.sp, maxLines = 1)
                            }
                            CcBadge(t.cc, t.id in queued, Deck.ink)
                            Text(TapeNames.duration(t.durationMs), color = Deck.ink, fontFamily = Mono, fontSize = 12.sp)
                        }
                        Box(Modifier.width(6.dp))
                        Box(Modifier.size(10.dp).clip(RoundedCornerShape(5.dp)).background(if (isPlay) Deck.led else Color(0xFF555555)))
                        }
                        LoadKey(enabled = inDeck != t.id) { onLoad(t) }
                    }
                    if (isPlay) {
                        Box(Modifier.fillMaxWidth().height(3.dp).background(Color.Black)) {
                            Box(Modifier.fillMaxWidth(progress).fillMaxHeight().background(Deck.orange))
                        }
                    }
                }
            }
            item { Spacer(Modifier.height(4.dp)) }
        }
        Box(Modifier.width(12.dp).fillMaxHeight().background(side))
    }
}

private val steelBrush = Brush.verticalGradient(listOf(Color(0xFF9AA1A8), Color(0xFF5B6168), Color(0xFF7D848B)))

/** Under the shelf: the steel door to the vault. */
@Composable
private fun VaultBar(onClick: () -> Unit) {
    val open by Vault.open.collectAsStateWithLifecycle()
    val ctx = LocalContext.current
    val shape = RoundedCornerShape(6.dp)
    Row(
        Modifier
            .fillMaxWidth()
            .height(48.dp)
            .shadow(3.dp, shape)
            .clip(shape)
            .background(steelBrush)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(if (open) "🔓" else "🔒", fontSize = 18.sp)
        Spacer(Modifier.width(10.dp))
        Text(
            stringResource(R.string.vault), color = Color(0xFF15181B), fontFamily = Mono, fontWeight = FontWeight.Bold,
            fontSize = 15.sp, modifier = Modifier.weight(1f)
        )
        Text(
            if (open) (Vault.count(ctx) ?: 0).let { pluralStringResource(R.plurals.n_tapes, it, it) + " · " + stringResource(R.string.vault_open) }
            else stringResource(R.string.vault_locked),
            color = Color(0xFF15181B), fontFamily = Mono, fontSize = 12.sp
        )
    }
}

/** The closed vault: a steel door with a dial, plus whatever is stopping it from opening. */
@Composable
private fun VaultDoor(problem: DoorProblem?, modifier: Modifier, onUnlock: () -> Unit, onReset: () -> Unit) {
    val ctx = LocalContext.current
    // Re-checked on resume (TapeStore bumps then), e.g. after setting up a screen lock.
    val v by TapeStore.version.collectAsStateWithLifecycle()
    val secure = remember(v) { Vault.deviceSecure(ctx) }
    Column(
        modifier
            .clip(RoundedCornerShape(10.dp))
            .background(steelBrush)
            .border(3.dp, Color(0xFF3A3F45), RoundedCornerShape(10.dp))
            .verticalScroll(rememberScrollState())
            .padding(18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically)
    ) {
        val ink = Color(0xFF15181B)
        Box(
            Modifier.size(96.dp).clip(RoundedCornerShape(48.dp))
                .background(Brush.radialGradient(listOf(Color(0xFFC9CED3), Color(0xFF4A4F55))))
                .border(4.dp, Color(0xFF2C3035), RoundedCornerShape(48.dp)),
            contentAlignment = Alignment.Center
        ) { Text("🔒", fontSize = 36.sp) }

        val text = when {
            problem == DoorProblem.LOST ->
                stringResource(R.string.vault_lost)
            !secure ->
                stringResource(R.string.vault_no_lock)
            else ->
                stringResource(R.string.vault_about)
        }
        Text(text, color = ink, fontFamily = Mono, fontSize = 13.sp, textAlign = TextAlign.Center)

        when {
            problem == DoorProblem.LOST ->
                DeckKey(stringResource(R.string.vault_reset), Modifier.fillMaxWidth(), textColor = Deck.red, onClick = onReset)
            !secure ->
                DeckKey(stringResource(R.string.vault_open_settings), Modifier.fillMaxWidth()) {
                    runCatching { ctx.startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS)) }
                }
            else -> DeckKey(stringResource(R.string.vault_unlock), Modifier.fillMaxWidth(), onClick = onUnlock)
        }
    }
}

/** SEND: as recorded, or a copy with the tape sound (Setup's TAPE EFFECTS) baked in. */
@Composable
private fun SendDialog(n: Int, onPlain: () -> Unit, onTapeSound: () -> Unit, onSetup: () -> Unit, onDismiss: () -> Unit) {
    val fx by Prefs.fx.collectAsStateWithLifecycle()
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Deck.panel,
        titleContentColor = Deck.text,
        textContentColor = Deck.dim,
        title = { Text(pluralStringResource(R.plurals.send_n, n, n), fontFamily = Mono, fontWeight = FontWeight.Bold) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                DeckKey(stringResource(R.string.send_plain), Modifier.fillMaxWidth(), height = 46.dp) { onDismiss(); onPlain() }
                Text(stringResource(R.string.send_plain_help), fontFamily = Mono, fontSize = 12.sp)
                Spacer(Modifier.height(8.dp))
                DeckKey(stringResource(R.string.send_fx), Modifier.fillMaxWidth(), height = 46.dp, enabled = fx.any) { onDismiss(); onTapeSound() }
                Text(
                    if (fx.any) stringResource(R.string.send_fx_help)
                    else stringResource(R.string.send_fx_off),
                    fontFamily = Mono, fontSize = 12.sp
                )
                if (!fx.any) Text(
                    stringResource(R.string.send_open_setup), color = Deck.amber, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 12.sp,
                    modifier = Modifier.clickable { onDismiss(); onSetup() }.padding(vertical = 4.dp)
                )
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel), color = Deck.text, fontFamily = Mono) } }
    )
}
