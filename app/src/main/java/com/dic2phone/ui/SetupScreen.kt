package com.dic2phone.ui

import androidx.annotation.StringRes
import androidx.compose.ui.res.stringResource
import android.Manifest
import android.annotation.SuppressLint
import android.app.StatusBarManager
import android.app.role.RoleManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LifecycleResumeEffect
import android.app.WallpaperManager
import android.widget.Toast
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.size
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.text.style.TextAlign
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.dic2phone.ComboWidget
import com.dic2phone.CounterWidget
import com.dic2phone.DeckWallpaperService
import com.dic2phone.Feedback
import com.dic2phone.Prefs
import com.dic2phone.R
import com.dic2phone.RecWidget
import com.dic2phone.RecordTileService
import com.dic2phone.Transcriber
import com.dic2phone.Whisper
import com.dic2phone.Widgets

private enum class SetupTab(@StringRes val label: Int) {
    LOOK(R.string.setup_tab_look), REC(R.string.setup_tab_rec), PLAY(R.string.setup_tab_play),
    CC(R.string.setup_tab_text), MORE(R.string.setup_tab_more)
}

@Composable
fun SetupScreen(onBack: () -> Unit) {
    var tab by rememberSaveable { mutableStateOf(SetupTab.LOOK) }
    Column(
        Modifier
            .fillMaxSize()
            .safeDrawingPadding()
            .padding(horizontal = 12.dp)
            .padding(top = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            DeckKey(stringResource(R.string.back_deck), Modifier.width(96.dp), height = 40.dp) { onBack() }
            Spacer(Modifier.width(12.dp))
            SectionTitle(stringResource(R.string.setup_title))
        }
        // Tabs: a row of piano keys; the open one stays pressed down.
        KeyBank(
            SetupTab.entries.map { t ->
                BankKey(
                    stringResource(t.label), if (t == tab) "●" else "○", latched = t == tab,
                    labelColor = if (t == tab) Deck.amber else null,
                    glyphColor = if (t == tab) Deck.led else null,
                ) { tab = t }
            },
            40.dp
        )
        val ctx = LocalContext.current
        key(tab.ordinal) {
            Column(
                Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(bottom = 12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                when (tab) {
                    SetupTab.LOOK -> LookTab()
                    SetupTab.REC -> RecTab()
                    SetupTab.PLAY -> PlayTab()
                    SetupTab.CC -> CaptionsPanel()
                    SetupTab.MORE -> { About(ctx); Credits(ctx) }
                }
            }
        }
    }
}

@Composable
private fun LookTab() {
    val ctx = LocalContext.current
    val theme by Prefs.theme.collectAsStateWithLifecycle()
    LanguagePanel()
    Panel {
        PanelTitle(stringResource(R.string.setup_theme))
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Themes.all.forEach { p -> ThemeCard(p, p.id == theme) { Feedback.key(); Prefs.setTheme(p.id) } }
        }
    }

    val disc by Prefs.minidisc.collectAsStateWithLifecycle()
    val label by Prefs.tapeLabel.collectAsStateWithLifecycle()
    val typed by Prefs.labelTyped.collectAsStateWithLifecycle()
    var writing by remember { mutableStateOf(false) }
    if (writing) LabelDialog { writing = false }
    Panel {
        PanelTitle(stringResource(R.string.setup_in_deck))
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            DeckKey(
                sel(!disc, stringResource(R.string.setup_cassette)), Modifier.weight(1f), height = 40.dp
            ) { Prefs.setMinidisc(false) }
            DeckKey(
                sel(disc, stringResource(R.string.setup_minidisc)), Modifier.weight(1f), height = 40.dp
            ) { Prefs.setMinidisc(true) }
        }
        Text(
            stringResource(R.string.setup_label_now, if (label.isBlank()) stringResource(R.string.setup_label_blank) else label) +
                "\n" + stringResource(if (disc) R.string.setup_label_help_disc else R.string.setup_label_help_tape),
            color = Deck.dim, fontFamily = Mono, fontSize = 12.sp
        )
        DeckKey(stringResource(R.string.setup_write_label), Modifier.fillMaxWidth(), height = 40.dp) { writing = true }
        Text(stringResource(R.string.setup_label_writing), color = Deck.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 13.sp)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            DeckKey(sel(!typed, stringResource(R.string.setup_handwritten)), Modifier.weight(1f), height = 40.dp) { Prefs.setLabelTyped(false) }
            DeckKey(sel(typed, stringResource(R.string.setup_typed)), Modifier.weight(1f), height = 40.dp) { Prefs.setLabelTyped(true) }
        }
        CassetteView(
            label.ifBlank { stringResource(R.string.setup_label_sample) }, if (disc) "MD 74 · SP · STEREO" else "C-60 · TYPE I · NORMAL",
            spinning = false, progress = .3f,
            modifier = Modifier.fillMaxWidth(.6f).align(Alignment.CenterHorizontally), handwritten = true
        )
        Text(
            stringResource(R.string.setup_label_writing_help),
            color = Deck.dim, fontFamily = Mono, fontSize = 11.sp
        )
    }

    Panel {
        PanelTitle(stringResource(R.string.setup_home))
        Text(
            stringResource(R.string.setup_wallpaper_help),
            color = Deck.dim, fontFamily = Mono, fontSize = 12.sp
        )
        DeckKey(stringResource(R.string.setup_set_wallpaper), Modifier.fillMaxWidth(), height = 40.dp) { setWallpaper(ctx) }
        Text(
            stringResource(R.string.setup_widgets_help),
            color = Deck.dim, fontFamily = Mono, fontSize = 12.sp
        )
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            DeckKey(stringResource(R.string.setup_w_counter), Modifier.weight(1f), height = 40.dp) { pinWidget(ctx, CounterWidget::class.java) }
            DeckKey(stringResource(R.string.setup_w_rec), Modifier.weight(1f), height = 40.dp) { pinWidget(ctx, RecWidget::class.java) }
            DeckKey(stringResource(R.string.setup_w_both), Modifier.weight(1f), height = 40.dp) { pinWidget(ctx, ComboWidget::class.java) }
        }
    }
}

/** The app's own language; PHONE follows the system. */
@Composable
private fun LanguagePanel() {
    val ctx = LocalContext.current
    val cur = remember { com.dic2phone.Lang.current(ctx) }
    Panel {
        PanelTitle(stringResource(R.string.setup_app_lang))
        com.dic2phone.Lang.ALL.chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                row.forEach { (tag, name) ->
                    val label = if (tag.isEmpty()) stringResource(R.string.setup_app_lang_phone) else name.uppercase()
                    DeckKey(sel(tag == cur, label), Modifier.weight(1f), height = 40.dp) {
                        if (tag != cur) (ctx as? android.app.Activity)?.let { com.dic2phone.Lang.set(it, tag) }
                    }
                }
            }
        }
        Text(stringResource(R.string.setup_app_lang_help), color = Deck.dim, fontFamily = Mono, fontSize = 11.sp)
    }
}

@Composable
private fun RecTab() {
    val ctx = LocalContext.current
    var tick by remember { mutableIntStateOf(0) }
    LifecycleResumeEffect(Unit) {
        tick++
        onPauseOrDispose { }
    }
    // Statuses are re-read whenever `tick` changes (on resume / after permission dialogs).
    val perms = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { tick++ }

    val snap by Prefs.snap.collectAsStateWithLifecycle()
    val vox by Prefs.vox.collectAsStateWithLifecycle()
    val voxSens by Prefs.voxSens.collectAsStateWithLifecycle()
    val location by Prefs.location.collectAsStateWithLifecycle()
    val locPerms = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { r ->
        if (r.values.any { it }) Prefs.setLocation(true)
        else Toast.makeText(ctx, ctx.getString(R.string.setup_loc_denied), Toast.LENGTH_SHORT).show()
    }
    Panel {
        PanelTitle(stringResource(R.string.setup_recording))
        Text(
            stringResource(R.string.setup_lock_help),
            color = Deck.dim, fontFamily = Mono, fontSize = 12.sp
        )
        Toggle(
            stringResource(R.string.setup_snap),
            stringResource(R.string.setup_snap_help),
            snap
        ) { Prefs.setSnap(!snap) }
        Toggle(
            stringResource(R.string.setup_vox),
            stringResource(R.string.setup_vox_help),
            vox
        ) { Prefs.setVox(!vox) }
        if (vox) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf(stringResource(R.string.setup_sens_low), stringResource(R.string.setup_sens_med), stringResource(R.string.setup_sens_high)).forEachIndexed { i, l ->
                DeckKey(if (voxSens == i) "● $l" else l, Modifier.weight(1f), height = 40.dp) { Prefs.setVoxSens(i) }
            }
        }
        if (vox) Text(
            stringResource(R.string.setup_sens_help),
            color = Deck.dim, fontFamily = Mono, fontSize = 11.sp
        )
        Toggle(
            stringResource(R.string.setup_where),
            stringResource(R.string.setup_where_help),
            location
        ) {
            when {
                location -> Prefs.setLocation(false)
                granted(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) -> Prefs.setLocation(true)
                else -> locPerms.launch(
                    arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
                )
            }
        }
    }

    val mic by Prefs.mic.collectAsStateWithLifecycle()
    val mics = remember(tick) { runCatching { com.dic2phone.Mics.list(ctx) }.getOrDefault(emptyList()) }
    Panel {
        PanelTitle(stringResource(R.string.setup_mic))
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            DeckKey(sel(mic.isBlank(), stringResource(R.string.auto)), Modifier.fillMaxWidth(), height = 40.dp) { Prefs.setMic("") }
            mics.forEach { m ->
                DeckKey(if (mic == m.key) "● ${m.label}" else m.label, Modifier.fillMaxWidth(), height = 40.dp) { Prefs.setMic(m.key) }
            }
        }
        val missing = mic.isNotBlank() && mics.none { it.key == mic }
        Text(
            stringResource(R.string.setup_mic_help) +
                if (missing) "\n" + stringResource(R.string.setup_mic_missing) else "",
            color = if (missing) Deck.orange else Deck.dim, fontFamily = Mono, fontSize = 11.sp
        )
    }

    val headset by Prefs.headset.collectAsStateWithLifecycle()
    val tidyDays by Prefs.tidyDays.collectAsStateWithLifecycle()
    Panel {
        PanelTitle(stringResource(R.string.setup_headset_tidy))
        Toggle(
            stringResource(R.string.setup_headset),
            stringResource(R.string.setup_headset_help),
            headset
        ) { Prefs.setHeadset(!headset) }
        Text(stringResource(R.string.setup_tidy), color = Deck.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 13.sp)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf(0 to stringResource(R.string.off)) + listOf(7, 14, 30, 90).map { it to stringResource(R.string.setup_days_short, it) }.forEach { (d, l) ->
                DeckKey(if (tidyDays == d) "● $l" else l, Modifier.weight(1f), height = 40.dp) { Prefs.setTidyDays(d) }
            }
        }
        Text(
            stringResource(R.string.setup_tidy_help, com.dic2phone.Tidy.WARN_DAYS),
            color = Deck.dim, fontFamily = Mono, fontSize = 11.sp
        )
    }

    val sounds by Prefs.sounds.collectAsStateWithLifecycle()
    val hiss by Prefs.hiss.collectAsStateWithLifecycle()
    Panel {
        PanelTitle(stringResource(R.string.setup_sound))
        Toggle(stringResource(R.string.setup_deck_sounds), stringResource(R.string.setup_deck_sounds_help), sounds) {
            Prefs.setSounds(!sounds); if (!sounds) Feedback.key()
        }
        Toggle(
            stringResource(R.string.setup_rec_hiss),
            stringResource(R.string.setup_rec_hiss_help),
            hiss && sounds, enabled = sounds
        ) { Prefs.setHiss(!hiss) }
    }

    SectionTitle(stringResource(R.string.setup_triggers), Modifier.padding(top = 6.dp))

    key(tick) {
        SetupItem(
            stringResource(R.string.setup_mic), stringResource(R.string.setup_mic_perm), granted(ctx, Manifest.permission.RECORD_AUDIO), stringResource(R.string.setup_grant)
        ) { perms.launch(arrayOf(Manifest.permission.RECORD_AUDIO)) }

        if (Build.VERSION.SDK_INT >= 33) SetupItem(
            stringResource(R.string.setup_notifs),
            stringResource(R.string.setup_notifs_help),
            granted(ctx, Manifest.permission.POST_NOTIFICATIONS), stringResource(R.string.setup_grant)
        ) { perms.launch(arrayOf(Manifest.permission.POST_NOTIFICATIONS)) }

        SetupItem(
            stringResource(R.string.setup_voldown),
            stringResource(R.string.setup_voldown_help),
            a11yEnabled(ctx), stringResource(R.string.setup_open)
        ) { ctx.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) }

        SetupItem(
            stringResource(R.string.setup_assist),
            stringResource(R.string.setup_assist_help),
            assistantHeld(ctx), stringResource(R.string.setup_open)
        ) {
            runCatching { ctx.startActivity(Intent(Settings.ACTION_VOICE_INPUT_SETTINGS)) }
                .onFailure { ctx.startActivity(Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)) }
        }

        SetupItem(
            stringResource(R.string.setup_side),
            stringResource(R.string.setup_side_help),
            null, stringResource(R.string.setup_open)
        ) {
            runCatching {
                ctx.startActivity(Intent().setClassName("com.android.settings", "com.android.settings.Settings\$FunctionKeySettingsActivity"))
            }.onFailure { ctx.startActivity(Intent(Settings.ACTION_SETTINGS)) }
        }

        if (Build.VERSION.SDK_INT >= 33) SetupItem(
            stringResource(R.string.setup_tile), stringResource(R.string.setup_tile_help, stringResource(R.string.tile_label)), null, stringResource(R.string.setup_add)
        ) { addTile(ctx) }

        SetupItem(
            stringResource(R.string.setup_battery),
            stringResource(R.string.setup_battery_help),
            ctx.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(ctx.packageName),
            stringResource(R.string.setup_allow)
        ) { requestBattery(ctx) }
    }
}

@Composable
private fun PlayTab() {
    val fx by Prefs.fx.collectAsStateWithLifecycle()
    val fxPlay by Prefs.fxPlay.collectAsStateWithLifecycle()
    val speed by Prefs.speed.collectAsStateWithLifecycle()
    val tapePitch by Prefs.tapePitch.collectAsStateWithLifecycle()
    val skip by Prefs.skipSilence.collectAsStateWithLifecycle()
    val wind by Prefs.tapeWind.collectAsStateWithLifecycle()
    Panel {
        PanelTitle(stringResource(R.string.setup_playback))
        Text(stringResource(R.string.setup_speed), color = Deck.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 13.sp)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Prefs.SPEEDS.forEach { (v, l) ->
                DeckKey(if (speed == v) "●$l×" else "$l×", Modifier.weight(1f), height = 40.dp) { Prefs.setSpeed(v) }
            }
        }
        Text(stringResource(R.string.setup_pitch), color = Deck.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 13.sp)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            DeckKey(sel(!tapePitch, stringResource(R.string.setup_pitch_natural)), Modifier.weight(1f), height = 40.dp) { Prefs.setTapePitch(false) }
            DeckKey(sel(tapePitch, stringResource(R.string.setup_pitch_tape)), Modifier.weight(1f), height = 40.dp) { Prefs.setTapePitch(true) }
        }
        Text(
            stringResource(R.string.setup_pitch_help),
            color = Deck.dim, fontFamily = Mono, fontSize = 11.sp
        )
        Toggle(
            stringResource(R.string.setup_skip),
            stringResource(R.string.setup_skip_help),
            skip
        ) { Prefs.setSkipSilence(!skip) }
        Toggle(stringResource(R.string.setup_wind), stringResource(R.string.setup_wind_help), wind) { Prefs.setTapeWind(!wind) }
    }
    Panel {
        PanelTitle(stringResource(R.string.setup_fx))
        Text(
            stringResource(R.string.setup_fx_help),
            color = Deck.dim, fontFamily = Mono, fontSize = 12.sp
        )
        Toggle(stringResource(R.string.setup_fx_hiss), stringResource(R.string.setup_fx_hiss_help), fx.hiss) {
            Prefs.setFx(fx.copy(hiss = !fx.hiss))
        }
        Toggle(stringResource(R.string.setup_fx_muffle), stringResource(R.string.setup_fx_muffle_help), fx.muffle) {
            Prefs.setFx(fx.copy(muffle = !fx.muffle))
        }
        Toggle(stringResource(R.string.setup_fx_wow), stringResource(R.string.setup_fx_wow_help), fx.wow) {
            Prefs.setFx(fx.copy(wow = !fx.wow))
        }
        Toggle(stringResource(R.string.setup_fx_sat), stringResource(R.string.setup_fx_sat_help), fx.saturate) {
            Prefs.setFx(fx.copy(saturate = !fx.saturate))
        }
        Toggle(
            stringResource(R.string.setup_fx_play),
            stringResource(R.string.setup_fx_play_help),
            fxPlay && fx.any, enabled = fx.any
        ) { Prefs.setFxPlay(!fxPlay) }
    }
    FxCopies()
}

/** Kept effect copies: how many / how big, when to throw unplayed ones out, and CLEAR NOW. */
@Composable
private fun FxCopies() {
    val ctx = LocalContext.current
    val keep by Prefs.fxKeepDays.collectAsStateWithLifecycle()
    var usage by remember { mutableStateOf(0 to 0L) }
    var cleared by remember { mutableStateOf(0) }
    LaunchedEffect(cleared) {
        // Refreshed now and then: idle renders and deck warm-ups add copies in the background.
        while (true) {
            usage = withContext(Dispatchers.IO) { com.dic2phone.LoFi.usage(ctx) }
            delay(5_000)
        }
    }
    Panel {
        PanelTitle(stringResource(R.string.setup_fx_copies))
        Text(
            stringResource(R.string.setup_fx_copies_info, usage.first, android.text.format.Formatter.formatShortFileSize(ctx, usage.second)),
            color = Deck.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 13.sp
        )
        Text(stringResource(R.string.setup_fx_copies_help), color = Deck.dim, fontFamily = Mono, fontSize = 11.sp)
        Text(stringResource(R.string.setup_fx_keep), color = Deck.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 13.sp)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            (listOf(0 to stringResource(R.string.off)) + listOf(30, 90, 180).map { it to stringResource(R.string.setup_days_short, it) }).forEach { (d, l) ->
                DeckKey(if (keep == d) "● $l" else l, Modifier.weight(1f), height = 40.dp) { Prefs.setFxKeepDays(d) }
            }
        }
        DeckKey(stringResource(R.string.setup_fx_clear), Modifier.fillMaxWidth(), height = 44.dp, enabled = usage.first > 0) {
            com.dic2phone.LoFi.clear(ctx); cleared++
        }
    }
}

/** Where the source lives (also in the README / NOTICE). */
private const val REPO_URL = "https://github.com/WolfyD/dic2phone"
private const val AUTHOR_MAIL = "wolfyden@gmail.com"

private fun open(ctx: Context, url: String) {
    runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
}

/** What the app is, who made it, its license (and the sounds that aren't under it), how it was made. */
@Composable
private fun About(ctx: Context) {
    Panel {
        PanelTitle(stringResource(R.string.setup_about))
        Text(stringResource(R.string.setup_about_text), color = Deck.dim, fontFamily = Mono, fontSize = 12.sp)
        val version = remember {
            runCatching { ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName }.getOrNull().orEmpty()
        }
        Text(
            "Dic2Phone $version\n© 2026 WolfyD · $AUTHOR_MAIL",
            Modifier.clip(RoundedCornerShape(6.dp)).clickable { open(ctx, "mailto:$AUTHOR_MAIL") }.padding(vertical = 2.dp),
            color = Deck.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 13.sp
        )
        Text(stringResource(R.string.setup_about_license), color = Deck.dim, fontFamily = Mono, fontSize = 12.sp)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            DeckKey(stringResource(R.string.setup_about_source), Modifier.weight(1f), height = 40.dp) { open(ctx, REPO_URL) }
            DeckKey("GPL-3.0 ↗", Modifier.weight(1f), height = 40.dp) { open(ctx, "https://www.gnu.org/licenses/gpl-3.0.html") }
        }
        Text(stringResource(R.string.setup_privacy), color = Deck.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 13.sp)
        Text(stringResource(R.string.setup_privacy_text), color = Deck.dim, fontFamily = Mono, fontSize = 12.sp)
        // Fold-out: how the app was made.
        var ai by rememberSaveable { mutableStateOf(false) }
        Text(
            (if (ai) "▾  " else "▸  ") + stringResource(R.string.setup_ai),
            Modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp)).clickable { Feedback.key(); ai = !ai }.padding(vertical = 6.dp),
            color = Deck.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 13.sp
        )
        androidx.compose.animation.AnimatedVisibility(ai) {
            Text(stringResource(R.string.setup_ai_text), color = Deck.dim, fontFamily = Mono, fontSize = 12.sp)
        }
    }
}

/** [freesound]: originally shared on Freesound, re-hosted on Pixabay (credited as such). */
private class Credit(val title: String, val author: String, val url: String, val freesound: Boolean = true)

private val SOUND_CREDITS = listOf(
    Credit("Tape Player Sounds", "AldebaranCW", "https://pixabay.com/sound-effects/tape-player-sounds-90780/"),
    Credit("Cassette FFWW cassetera", "koraps", "https://pixabay.com/sound-effects/cassette-ffww-cassetera-96765/"),
    Credit("Cassette Eject", "Jurij", "https://pixabay.com/sound-effects/cassette-eject-172757/", freesound = false),
    Credit("Cassette Noise When Got In", "erikeah", "https://pixabay.com/sound-effects/cassette-noise-when-got-in-79504/"),
)

@Composable
private fun Credits(ctx: Context) {
    Panel {
        PanelTitle(stringResource(R.string.setup_cr_sounds))
        Text(
            stringResource(R.string.setup_cr_sounds_text),
            color = Deck.dim, fontFamily = Mono, fontSize = 12.sp
        )
        SOUND_CREDITS.forEach { c ->
            Column(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(6.dp))
                    .clickable { runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(c.url))) } }
                    .padding(vertical = 4.dp)
            ) {
                Text("“${c.title}”", color = Deck.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                Text(stringResource(if (c.freesound) R.string.setup_cr_by else R.string.setup_cr_by_px, c.author), color = Deck.dim, fontFamily = Mono, fontSize = 11.sp)
            }
        }
        DeckKey("PIXABAY LICENSE", Modifier.fillMaxWidth(), height = 40.dp) {
            runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://pixabay.com/service/license-summary/"))) }
        }
        PanelTitle(stringResource(R.string.setup_cr_hand))
        Text(
            stringResource(R.string.setup_cr_hand_text),
            color = Deck.dim, fontFamily = Mono, fontSize = 12.sp
        )
        DeckKey("OPEN FONT LICENSE", Modifier.fillMaxWidth(), height = 40.dp) {
            runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://openfontlicense.org"))) }
        }
        PanelTitle(stringResource(R.string.setup_cr_type))
        Text(
            stringResource(R.string.setup_cr_type_text),
            color = Deck.dim, fontFamily = Mono, fontSize = 12.sp
        )
        PanelTitle(stringResource(R.string.setup_cr_sw))
        Text(
            stringResource(R.string.setup_cr_sw_text),
            color = Deck.dim, fontFamily = Mono, fontSize = 12.sp
        )
        PanelTitle(stringResource(R.string.setup_cr_stt))
        Text(
            stringResource(R.string.setup_cr_stt_text),
            color = Deck.dim, fontFamily = Mono, fontSize = 12.sp
        )
        DeckKey("WHISPER.CPP", Modifier.fillMaxWidth(), height = 40.dp) {
            runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/ggml-org/whisper.cpp"))) }
        }
    }
}

private val CC_LANGS = listOf(
    "auto" to "AUTO", "en" to "EN", "hu" to "HU", "de" to "DE", "fr" to "FR", "es" to "ES",
    "it" to "IT", "pl" to "PL", "ro" to "RO", "nl" to "NL", "pt" to "PT", "cs" to "CS",
)

@Composable
private fun CaptionsPanel() {
    val ctx = LocalContext.current
    val model by Prefs.ccModel.collectAsStateWithLifecycle()
    val lang by Prefs.ccLang.collectAsStateWithLifecycle()
    val autoCc by Prefs.autoCc.collectAsStateWithLifecycle()
    val busy by Transcriber.status.collectAsStateWithLifecycle()
    val queued by Transcriber.queued.collectAsStateWithLifecycle()
    val err by Transcriber.lastError.collectAsStateWithLifecycle()
    var refresh by remember { mutableIntStateOf(0) }
    val installed = remember(refresh, busy, queued) { Transcriber.Model.entries.filter { Transcriber.installed(ctx, it) } }
    Panel {
        PanelTitle(stringResource(R.string.setup_cc))
        Text(
            stringResource(R.string.setup_cc_help) +
                if (!Whisper.available) "\n\n" + stringResource(R.string.setup_cc_no_arm) else "",
            color = Deck.dim, fontFamily = Mono, fontSize = 12.sp
        )
        Text(stringResource(R.string.setup_cc_lang), color = Deck.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 13.sp)
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            CC_LANGS.forEach { (code, l) ->
                val label = if (code == "auto") stringResource(R.string.auto) else l
                DeckKey(
                    if (code == lang) "● $label" else label, Modifier.width(if (code == "auto") 84.dp else 60.dp), height = 40.dp
                ) { Prefs.setCcLang(code) }
            }
        }
        Text(
            stringResource(R.string.setup_cc_lang_help),
            color = Deck.dim, fontFamily = Mono, fontSize = 11.sp
        )
        Text(stringResource(R.string.setup_cc_auto), color = Deck.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 13.sp)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf(Prefs.AUTO_CC_OFF to stringResource(R.string.off), Prefs.AUTO_CC_NOW to stringResource(R.string.setup_cc_after_rec), Prefs.AUTO_CC_IDLE to stringResource(R.string.setup_cc_idle)).forEach { (v, l) ->
                DeckKey(if (autoCc == v) "● $l" else l, Modifier.weight(1f), height = 40.dp) { Prefs.setAutoCc(v) }
            }
        }
        val noModel = installed.none { it.id == model }
        Text(
            stringResource(R.string.setup_cc_auto_help) +
                if (autoCc != Prefs.AUTO_CC_OFF && noModel) "\n" + stringResource(R.string.setup_cc_need_model) else "",
            color = if (autoCc != Prefs.AUTO_CC_OFF && noModel) Deck.orange else Deck.dim, fontFamily = Mono, fontSize = 11.sp
        )
        Text(stringResource(R.string.setup_cc_model), color = Deck.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 13.sp)
        Transcriber.Model.entries.forEach { m ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Led(m in installed, size = 10.dp)
                        Spacer(Modifier.width(8.dp))
                        Text(m.label, color = Deck.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                        Text(
                            if (m in installed) "  " + stringResource(R.string.setup_cc_downloaded) else "", color = Deck.led, fontFamily = Mono, fontSize = 11.sp
                        )
                    }
                    Text("${m.size} · " + stringResource(m.note), color = Deck.dim, fontFamily = Mono, fontSize = 11.sp)
                }
                Spacer(Modifier.width(8.dp))
                DeckKey(sel(model == m.id, stringResource(R.string.setup_cc_use)), Modifier.width(84.dp), height = 40.dp) { Prefs.setCcModel(m.id) }
            }
            if (m !in installed && Whisper.available) {
                val fetching = Transcriber.fetchId(m) in queued
                val st = busy?.takeIf { it.tapeId == null && it.line.contains(m.label) }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (fetching) {
                        Text(
                            if (st != null) stringResource(R.string.setup_cc_downloading, st.pct) else stringResource(R.string.setup_cc_waiting),
                            color = Deck.led, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 12.sp,
                            modifier = Modifier.weight(1f)
                        )
                        DeckKey(stringResource(R.string.cancel), Modifier.width(96.dp), height = 40.dp, textColor = Deck.red) { Transcriber.cancelAll() }
                    } else {
                        DeckKey(stringResource(R.string.setup_cc_download, m.size), Modifier.weight(1f), height = 40.dp) {
                            Transcriber.fetch(ctx, m)
                        }
                    }
                }
            }
        }
        err?.let { Text("⚠ $it", color = Deck.orange, fontFamily = Mono, fontSize = 11.sp) }
        Text(
            stringResource(R.string.setup_cc_source),
            color = Deck.dim, fontFamily = Mono, fontSize = 11.sp
        )
        DeckKey(
            stringResource(R.string.setup_cc_delete), Modifier.fillMaxWidth(), height = 40.dp,
            enabled = installed.isNotEmpty() && busy == null, textColor = Deck.red
        ) {
            Transcriber.deleteModels(ctx)
            refresh++
            Toast.makeText(ctx, ctx.getString(R.string.setup_cc_deleted), Toast.LENGTH_SHORT).show()
        }
    }
}

@Composable
private fun key(k: Int, content: @Composable () -> Unit) = androidx.compose.runtime.key(k) { content() }

@Composable
private fun Panel(content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(Deck.panel)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        content = content
    )
}

@Composable
private fun PanelTitle(text: String) =
    Text(text, color = Deck.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 15.sp)

@Composable
private fun Toggle(title: String, text: String, on: Boolean, enabled: Boolean = true, onClick: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.alpha(if (enabled) 1f else .45f)) {
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Led(on, size = 12.dp)
                Spacer(Modifier.width(8.dp))
                Text(title, color = Deck.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 13.sp)
            }
            Text(text, color = Deck.dim, fontFamily = Mono, fontSize = 11.sp)
        }
        Spacer(Modifier.width(8.dp))
        DeckKey(stringResource(if (on) R.string.on else R.string.off), Modifier.width(72.dp), height = 40.dp, enabled = enabled, onClick = onClick)
    }
}

/** Mini preview: the theme's background with a cassette drawn in its colours. */
@Composable
private fun ThemeCard(p: Palette, selected: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(8.dp)
    Column(
        Modifier
            .width(132.dp)
            .clip(shape)
            .border(if (selected) 3.dp else 1.dp, if (selected) p.accent else Color.Black.copy(alpha = .4f), shape)
            .drawBehind { drawIntoCanvas { DeckArt.background(it.nativeCanvas, size.width, size.height, p) } }
            .clickable(onClick = onClick)
            .padding(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Canvas(Modifier.fillMaxWidth().aspectRatio(DeckArt.CASSETTE_RATIO)) {
            drawIntoCanvas { DeckArt.cassette(it.nativeCanvas, size.width, p, "", "", 0f, .3f) }
        }
        Row {
            p.stripes.forEach { Box(Modifier.size((48 / p.stripes.size).dp, 3.dp).background(it)) }
        }
        Text(
            p.name, color = p.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 10.sp,
            maxLines = 1, textAlign = TextAlign.Center
        )
        Text(
            if (selected) "● " + stringResource(R.string.setup_theme_loaded) else " ", color = p.accent, fontFamily = Mono, fontSize = 9.sp
        )
    }
}

private fun setWallpaper(ctx: Context) {
    val cn = ComponentName(ctx, DeckWallpaperService::class.java)
    runCatching {
        ctx.startActivity(
            Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER)
                .putExtra(WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT, cn)
        )
    }.recoverCatching {
        ctx.startActivity(Intent(WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER))
    }.onFailure {
        Toast.makeText(ctx, ctx.getString(R.string.setup_no_live_wp), Toast.LENGTH_SHORT).show()
    }
}

private fun pinWidget(ctx: Context, cls: Class<*>) {
    if (!Widgets.pin(ctx, cls)) {
        Toast.makeText(ctx, ctx.getString(R.string.setup_widget_hint), Toast.LENGTH_LONG).show()
    }
}

@Composable
private fun SetupItem(title: String, text: String, ok: Boolean?, button: String, onClick: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(Deck.panel)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (ok != null) {
                Led(ok, size = 12.dp)
                Spacer(Modifier.width(8.dp))
            }
            Text(title, color = Deck.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 15.sp, modifier = Modifier.weight(1f))
            if (ok != null) Text(stringResource(if (ok) R.string.on else R.string.off), color = if (ok) Deck.led else Deck.dim, fontFamily = Mono, fontSize = 12.sp)
        }
        Text(text, color = Deck.dim, fontFamily = Mono, fontSize = 12.sp)
        DeckKey(button, Modifier.width(120.dp), height = 40.dp, onClick = onClick)
    }
}

private fun granted(ctx: Context, p: String) =
    ContextCompat.checkSelfPermission(ctx, p) == PackageManager.PERMISSION_GRANTED

fun a11yEnabled(ctx: Context): Boolean {
    val s = Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
    return s.split(':').any { ComponentName.unflattenFromString(it)?.packageName == ctx.packageName }
}

private fun assistantHeld(ctx: Context): Boolean =
    runCatching { ctx.getSystemService(RoleManager::class.java).isRoleHeld(RoleManager.ROLE_ASSISTANT) }
        .getOrDefault(false)

@SuppressLint("BatteryLife")
private fun requestBattery(ctx: Context) {
    runCatching {
        ctx.startActivity(
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${ctx.packageName}"))
        )
    }.onFailure { ctx.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) }
}

private fun addTile(ctx: Context) {
    if (Build.VERSION.SDK_INT < 33) return
    ctx.getSystemService(StatusBarManager::class.java).requestAddTileService(
        ComponentName(ctx, RecordTileService::class.java),
        ctx.getString(R.string.tile_label),
        Icon.createWithResource(ctx, R.drawable.ic_cassette),
        ctx.mainExecutor
    ) { }
}
