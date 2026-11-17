package com.dic2phone

import android.content.Context
import android.content.SharedPreferences
import com.dic2phone.ui.Deck
import com.dic2phone.ui.Themes
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** User settings. Initialised once in [App.onCreate]. */
object Prefs {
    private lateinit var sp: SharedPreferences
    lateinit var app: Context
        private set

    private val _sounds = MutableStateFlow(true)
    val sounds: StateFlow<Boolean> = _sounds
    /** Faint monitor hiss in the speaker/headphones while recording (never on the tape). */
    private val _hiss = MutableStateFlow(true)
    val hiss: StateFlow<Boolean> = _hiss
    private val _theme = MutableStateFlow(Themes.Walnut.id)
    val theme: StateFlow<String> = _theme
    /** Effects baked into LO-FI copies (and heard on playback if [fxPlay]). */
    private val _fx = MutableStateFlow(TapeFx())
    val fx: StateFlow<TapeFx> = _fx
    private val _fxPlay = MutableStateFlow(false)
    val fxPlay: StateFlow<Boolean> = _fxPlay
    /** Effect copies not played for this many days are deleted (0 = kept until cleared). */
    private val _fxKeepDays = MutableStateFlow(0)
    val fxKeepDays: StateFlow<Int> = _fxKeepDays
    /** What the user wrote on the deck's tape label (just decoration). Empty = unlabelled. */
    private val _tapeLabel = MutableStateFlow("")
    val tapeLabel: StateFlow<String> = _tapeLabel
    /** Show a MiniDisc instead of a cassette. */
    private val _minidisc = MutableStateFlow(false)
    val minidisc: StateFlow<Boolean> = _minidisc

    /** The user's label text is typed (typewriter) rather than handwritten. */
    private val _labelTyped = MutableStateFlow(false)
    val labelTyped: StateFlow<Boolean> = _labelTyped

    /** Speech model for captions: "" = not chosen yet, "base" or "small". */
    private val _ccModel = MutableStateFlow("")
    val ccModel: StateFlow<String> = _ccModel
    /** Caption language: "auto" or a whisper language code ("en", "hu", ...). */
    private val _ccLang = MutableStateFlow("auto")
    val ccLang: StateFlow<String> = _ccLang

    /** Flag a moment by snapping your fingers while recording. */
    private val _snap = MutableStateFlow(true)
    val snap: StateFlow<Boolean> = _snap
    /** Locked (latched) recordings only roll while there's sound. */
    private val _vox = MutableStateFlow(false)
    val vox: StateFlow<Boolean> = _vox
    /** Noise-activated sensitivity: 0 = only loud sound, 1 = speech nearby, 2 = quiet sound too. */
    private val _voxSens = MutableStateFlow(1)
    val voxSens: StateFlow<Int> = _voxSens
    /** Note where each tape was recorded. */
    private val _location = MutableStateFlow(false)
    val location: StateFlow<Boolean> = _location

    /** The speeds on offer (Setup keys and the deck's varispeed fader), with their labels. */
    val SPEEDS = listOf(0.75f to "¾", 1f to "1", 1.25f to "1¼", 1.5f to "1½", 2f to "2")
    /** Playback speed (1 = as recorded). */
    private val _speed = MutableStateFlow(1f)
    val speed: StateFlow<Float> = _speed
    /** Off-speed playback changes the pitch too, like a real tape (else the voice keeps its pitch). */
    private val _tapePitch = MutableStateFlow(false)
    val tapePitch: StateFlow<Boolean> = _tapePitch
    /** Jump over long silences when playing. */
    private val _skipSilence = MutableStateFlow(false)
    val skipSilence: StateFlow<Boolean> = _skipSilence
    /** Holding REW / FF winds the tape smoothly (motor sound), instead of repeating 10 s skips. */
    private val _tapeWind = MutableStateFlow(false)
    val tapeWind: StateFlow<Boolean> = _tapeWind
    /** The deck's CUE key (only with [tapeWind]): winding plays the tape fast, so you hear where you are. */
    private val _windCue = MutableStateFlow(false)
    val windCue: StateFlow<Boolean> = _windCue
    /** Captions for new tapes by themselves: [AUTO_CC_OFF], [AUTO_CC_NOW] or [AUTO_CC_IDLE]. */
    private val _autoCc = MutableStateFlow(AUTO_CC_OFF)
    val autoCc: StateFlow<Int> = _autoCc
    /** Headset button: hold to lock REC on / off, press while recording to flag. */
    private val _headset = MutableStateFlow(false)
    val headset: StateFlow<Boolean> = _headset
    /** Microphone to record with ([Mics] key), "" = the phone decides. */
    private val _mic = MutableStateFlow("")
    val mic: StateFlow<String> = _mic
    /** Auto-tidy: heard deck tapes older than this many days are deleted. 0 = never. */
    private val _tidyDays = MutableStateFlow(0)
    val tidyDays: StateFlow<Int> = _tidyDays
    /** Hidden test hook: length of a "day" for auto-tidy, in seconds. */
    val tidyDayMs: Long get() = sp.getLong("debug_tidy_day_s", 86_400L).coerceIn(60L, 86_400L) * 1000L

    /** Tape order per list ("deck", "shelf", "vault"): a [TapeSort] name. */
    private val _sorts = MutableStateFlow(emptyMap<String, TapeSort>())
    val sorts: StateFlow<Map<String, TapeSort>> = _sorts
    fun setSort(list: String, s: TapeSort) {
        _sorts.value = _sorts.value + (list to s)
        sp.edit().putString("sort_$list", s.name).apply()
    }

    /** The tape left in the deck's player (not vault tapes), "" = empty. */
    var deckTape: String
        get() = sp.getString("deck_tape", "")!!
        set(v) { sp.edit().putString("deck_tape", v).apply() }
    /** Hidden test hook: tape length before a long recording rolls onto a new tape. */
    val maxTapeSec: Int get() = sp.getInt("debug_max_tape_s", 3600).coerceIn(10, 3600)

    fun init(ctx: Context) {
        app = ctx.applicationContext
        sp = ctx.getSharedPreferences("settings", Context.MODE_PRIVATE)
        _sounds.value = sp.getBoolean("sounds", true)
        _hiss.value = sp.getBoolean("hiss", true)
        _theme.value = sp.getString("theme", Themes.Walnut.id)!!
        _fx.value = TapeFx(
            hiss = sp.getBoolean("fx_hiss", true),
            muffle = sp.getBoolean("fx_muffle", true),
            wow = sp.getBoolean("fx_wow", true),
            saturate = sp.getBoolean("fx_sat", true),
        )
        _fxPlay.value = sp.getBoolean("fx_play", false)
        _fxKeepDays.value = sp.getInt("fx_keep_days", 0)
        _tapeLabel.value = sp.getString("tape_label", "")!!
        _minidisc.value = sp.getBoolean("minidisc", false)
        _labelTyped.value = sp.getBoolean("label_typed", false)
        com.dic2phone.ui.DeckArt.typedLabels = _labelTyped.value
        _ccModel.value = sp.getString("cc_model", "")!!
        _ccLang.value = sp.getString("cc_lang", "auto")!!
        _snap.value = sp.getBoolean("snap", true)
        _vox.value = sp.getBoolean("vox", false)
        _voxSens.value = sp.getInt("vox_sens", 1)
        _location.value = sp.getBoolean("location", false)
        _speed.value = sp.getFloat("play_speed", 1f)
        _tapePitch.value = sp.getBoolean("tape_pitch", false)
        _skipSilence.value = sp.getBoolean("skip_silence", false)
        _tapeWind.value = sp.getBoolean("tape_wind", false)
        _windCue.value = sp.getBoolean("wind_cue", false)
        _autoCc.value = sp.getInt("auto_cc", AUTO_CC_OFF)
        _headset.value = sp.getBoolean("headset", false)
        _mic.value = sp.getString("mic", "")!!
        _tidyDays.value = sp.getInt("tidy_days", 0)
        _sorts.value = listOf("deck", "shelf", "vault").associateWith { k ->
            runCatching { TapeSort.valueOf(sp.getString("sort_$k", "")!!) }.getOrDefault(TapeSort.NEWEST)
        }
        Deck.palette = Themes.byId(_theme.value)
    }

    fun setSnap(on: Boolean) { _snap.value = on; sp.edit().putBoolean("snap", on).apply() }
    fun setVox(on: Boolean) { _vox.value = on; sp.edit().putBoolean("vox", on).apply() }
    fun setVoxSens(v: Int) { _voxSens.value = v; sp.edit().putInt("vox_sens", v).apply() }
    fun setLocation(on: Boolean) { _location.value = on; sp.edit().putBoolean("location", on).apply() }

    fun setSounds(on: Boolean) {
        _sounds.value = on
        sp.edit().putBoolean("sounds", on).apply()
        syncHiss()
    }

    fun setHiss(on: Boolean) {
        _hiss.value = on
        sp.edit().putBoolean("hiss", on).apply()
        syncHiss()
    }

    private fun syncHiss() {
        if (_sounds.value && _hiss.value && Recorder.state.value.recording) Feedback.hissStart(app)
        else Feedback.hissStop()
    }

    fun setTheme(id: String) {
        _theme.value = id
        Deck.palette = Themes.byId(id)
        sp.edit().putString("theme", id).apply()
    }

    fun setFx(fx: TapeFx) {
        _fx.value = fx
        sp.edit()
            .putBoolean("fx_hiss", fx.hiss).putBoolean("fx_muffle", fx.muffle)
            .putBoolean("fx_wow", fx.wow).putBoolean("fx_sat", fx.saturate)
            .apply()
        FxPrep.sync(app)
    }

    fun setFxPlay(on: Boolean) {
        _fxPlay.value = on
        sp.edit().putBoolean("fx_play", on).apply()
        FxPrep.sync(app)
    }

    fun setFxKeepDays(d: Int) { _fxKeepDays.value = d; sp.edit().putInt("fx_keep_days", d).apply() }

    fun setTapeLabel(text: String) {
        val t = text.trim().take(LABEL_MAX)
        _tapeLabel.value = t
        sp.edit().putString("tape_label", t).apply()
    }

    fun setMinidisc(on: Boolean) {
        _minidisc.value = on
        sp.edit().putBoolean("minidisc", on).apply()
    }

    fun setLabelTyped(on: Boolean) {
        _labelTyped.value = on
        com.dic2phone.ui.DeckArt.typedLabels = on
        sp.edit().putBoolean("label_typed", on).apply()
    }

    fun setCcModel(id: String) {
        _ccModel.value = id
        sp.edit().putString("cc_model", id).apply()
    }

    fun setCcLang(code: String) {
        _ccLang.value = code
        sp.edit().putString("cc_lang", code).apply()
    }

    fun setSpeed(v: Float) { _speed.value = v; sp.edit().putFloat("play_speed", v).apply(); Player.applySpeed() }
    fun setTapePitch(on: Boolean) { _tapePitch.value = on; sp.edit().putBoolean("tape_pitch", on).apply(); Player.applySpeed() }
    fun setSkipSilence(on: Boolean) { _skipSilence.value = on; sp.edit().putBoolean("skip_silence", on).apply(); Player.skipSilenceChanged(app) }
    fun setTapeWind(on: Boolean) { _tapeWind.value = on; sp.edit().putBoolean("tape_wind", on).apply() }
    fun setWindCue(on: Boolean) { _windCue.value = on; sp.edit().putBoolean("wind_cue", on).apply() }
    fun setAutoCc(v: Int) { _autoCc.value = v; sp.edit().putInt("auto_cc", v).apply(); AutoCaptions.sync(app) }
    fun setHeadset(on: Boolean) { _headset.value = on; sp.edit().putBoolean("headset", on).apply() }
    fun setMic(key: String) { _mic.value = key; sp.edit().putString("mic", key).apply() }
    fun setTidyDays(d: Int) { _tidyDays.value = d; sp.edit().putInt("tidy_days", d).apply(); Tidy.schedule(app); TapeStore.bump() }

    const val AUTO_CC_OFF = 0
    const val AUTO_CC_NOW = 1
    const val AUTO_CC_IDLE = 2

    const val LABEL_MAX = 40
}

/** How a tape list is ordered. */
enum class TapeSort {
    NEWEST, OLDEST, LONGEST, TITLE;

    fun next() = entries[(ordinal + 1) % entries.size]

    /** Titled tapes A–Z first (untitled ones after, newest first). */
    fun apply(list: List<Tape>): List<Tape> = when (this) {
        NEWEST -> list.sortedByDescending { it.id }
        OLDEST -> list.sortedBy { it.id }
        LONGEST -> list.sortedByDescending { it.durationMs }
        TITLE -> list.sortedWith(
            compareBy<Tape> { it.title.isBlank() }
                .thenBy(String.CASE_INSENSITIVE_ORDER) { it.title }
                .thenByDescending { it.id }
        )
    }
}
