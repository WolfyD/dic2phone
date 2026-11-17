package com.dic2phone

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin
import kotlin.random.Random

/**
 * Cassette-deck key sounds + haptics + the REC monitor hiss.
 *
 * The key sounds are real tape-deck recordings from Pixabay (see Credits in Setup), cut into
 * short clips and stored as raw 16-bit mono PCM at [CLIP_SR] in assets/sounds:
 *  - REC: fingertip contact, the REC/PLAY latch clacking in, the transport motor engaging.
 *  - STOP: STOP clacks down, the latched keys release, the mechanism drops with a thud.
 *  - two light key clicks, alternated at random for ordinary buttons.
 *  - EJECT (cassette popping out) and INSERT (cassette going in, door clicking shut).
 *  - the motor whirr of a tape winding (a seamless loop, for TAPE WIND).
 *
 * The clips are under the Pixabay Content License, not the app's GPL, and are kept out of the
 * public source (see NOTICE). Without them, [SynthKeys] makes stand-ins, so a build from
 * source still clicks.
 */
object Feedback {
    private const val CLIP_SR = 24_000
    private val startPcm by lazy { clip("key_rec") { SynthKeys.rec() } }
    private val stopPcm by lazy { clip("key_stop") { SynthKeys.stop() } }
    private val keyPcm by lazy { listOf(clip("key_soft1") { SynthKeys.key(1) }, clip("key_soft2") { SynthKeys.key(2) }) }
    private val hissPcm by lazy { Synth.hiss() }
    private val main = Handler(Looper.getMainLooper())

    /** Start sound length (+ margin); the recorder starts after it so the click isn't on tape. */
    const val START_SOUND_MS = 340L

    /**
     * REC hiss levels. In headphones nothing leaks onto the tape, so it follows the media volume.
     * On the speaker (which sits ~1 cm from the mic) it is pinned to an absolute level that is
     * independent of the media volume: measured on a Pixel 3 XL, 0.22 at 60 % media volume
     * leaked ~7 dB above a quiet room's noise floor; [HISS_SPEAKER_DB] below that puts the leak
     * under the room's own noise.
     */
    private const val HISS_HEADPHONES = 0.7f
    private const val HISS_SPEAKER_REF = 0.22f
    private const val HISS_SPEAKER_REF_VOL = 0.6f
    private const val HISS_SPEAKER_DB = -16f

    // Haptics follow the clips: contact ~12 ms, latch clack ~82 ms.
    fun recStart(ctx: Context) {
        play(startPcm, 0.5f, CLIP_SR)
        vibrate(ctx, longArrayOf(12, 10, 58, 40), intArrayOf(0, 90, 0, 255))
    }

    // STOP clack ~55 ms, keys release ~185 ms, mechanism thud ~280 ms.
    fun recStop(ctx: Context) {
        play(stopPcm, 0.5f, CLIP_SR)
        vibrate(ctx, longArrayOf(55, 35, 95, 15, 80, 30), intArrayOf(0, 255, 0, 140, 0, 200))
    }

    /** A flag was set while recording: a short tick you can feel (no sound, it'd be on the tape). */
    fun flag(ctx: Context) = vibrate(ctx, longArrayOf(0, 18), intArrayOf(0, 200))

    /** Recording locked on: two firm pulses (again no sound). */
    fun latch(ctx: Context) = vibrate(ctx, longArrayOf(0, 30, 70, 30), intArrayOf(0, 255, 0, 255))

    /** Menu/UI keys: quiet, these happen constantly. */
    fun key() = play(keyPcm.random(), 0.15f, CLIP_SR)

    private val detentPcm by lazy { Synth.detent() }

    /** The varispeed fader dropping into a notch: a small dry plastic tick, and one you can feel. */
    fun detent(ctx: Context) {
        play(detentPcm, 0.4f, Synth.SR)
        try {
            val v: Vibrator = if (Build.VERSION.SDK_INT >= 31)
                ctx.getSystemService(VibratorManager::class.java).defaultVibrator
            else
                @Suppress("DEPRECATION") ctx.getSystemService(Vibrator::class.java)
            v.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK))
        } catch (e: Exception) {
            Log.w("Feedback", "tick failed", e)
        }
    }

    private val doorOpenPcm by lazy { clip("tape_eject") { SynthKeys.eject() } }
    private val doorClosePcm by lazy { clip("tape_insert") { SynthKeys.insert() } }

    // Recorded clips (see Credits): haptics follow their clacks.
    /** EJECT: key travel, latch, and the cassette popping up (loudest, ~250 ms). */
    fun doorOpen(ctx: Context) {
        play(doorOpenPcm, 0.5f, CLIP_SR)
        vibrate(ctx, longArrayOf(70, 12, 78, 14, 76, 30), intArrayOf(0, 90, 0, 140, 0, 255))
    }

    /** A tape goes in: the shell slides into the well, then clunks home (~360 ms). */
    fun doorClose(ctx: Context) {
        play(doorClosePcm, 0.5f, CLIP_SR)
        vibrate(ctx, longArrayOf(10, 18, 332, 30), intArrayOf(0, 120, 0, 255))
    }

    /** A recorded clip from assets/sounds, or [standIn]'s (at [CLIP_SR]) if this build hasn't got it. */
    private fun clip(name: String, standIn: () -> ShortArray): ShortArray = try {
        val bytes = Prefs.app.assets.open("sounds/$name.pcm").use { it.readBytes() }
        val sb = java.nio.ByteBuffer.wrap(bytes).order(java.nio.ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        ShortArray(sb.remaining()).also { sb.get(it) }
    } catch (e: java.io.IOException) {
        Log.i("Feedback", "no $name clip in this build: synthesized")
        standIn()
    }

    // ---- TAPE WIND motor ---------------------------------------------------------------------

    private val windPcm by lazy { clip("tape_wind") { SynthKeys.wind() } }
    private var windTrack: AudioTrack? = null
    private const val WIND_VOL = 0.5f

    /** The reels start turning: the whirr loops until [windStop], pitched by [windSpeed]. */
    fun windStart() {
        if (windTrack != null || !Prefs.sounds.value) return
        val pcm = windPcm
        val t = buildTrack(pcm.size, CLIP_SR) ?: return
        try {
            t.write(pcm, 0, pcm.size)
            t.setLoopPoints(0, pcm.size, -1)
            windLevel(t, 0f)
            t.play()
            windTrack = t
        } catch (e: Exception) {
            Log.w("Feedback", "wind sound failed", e)
            t.release()
        }
    }

    /** [f] 0..1: the motor spinning up, so the whirr rises in pitch and level. */
    fun windSpeed(f: Float) { windTrack?.let { windLevel(it, f) } }

    private fun windLevel(t: AudioTrack, f: Float) = runCatching {
        t.playbackRate = (CLIP_SR * (0.8f + 0.35f * f)).toInt()
        t.setVolume(WIND_VOL * (0.65f + 0.35f * f))
    }

    fun windStop() {
        val t = windTrack ?: return
        windTrack = null
        runCatching { t.setVolume(0f); t.stop() }
        t.release()
    }

    /** Wound to the end of the tape: the whirr stops and the mechanism clunks off. */
    fun windEnd() {
        windStop()
        play(stopPcm, 0.35f, CLIP_SR)
    }

    // ---- REC monitor hiss ------------------------------------------------------------------

    private var hissTrack: AudioTrack? = null

    fun hissStart(ctx: Context) {
        if (hissTrack != null || !Prefs.sounds.value || !Prefs.hiss.value) return
        val pcm = hissPcm
        val t = buildTrack(pcm.size, Synth.SR) ?: return
        val target = if (headphones(ctx)) HISS_HEADPHONES else speakerHiss(ctx)
        t.write(pcm, 0, pcm.size)
        t.setLoopPoints(0, pcm.size, -1)
        t.setVolume(0f)
        t.play()
        hissTrack = t
        // Slow fade-in, like the head settling on the tape.
        for (i in 1..10) main.postDelayed({ if (hissTrack === t) t.setVolume(target * i / 10f) }, i * 40L)
    }

    fun hissStop() {
        val t = hissTrack ?: return
        hissTrack = null
        runCatching { t.stop() }
        t.release()
    }

    /** Track volume that gives the same acoustic hiss level at any media volume setting. */
    private fun speakerHiss(ctx: Context): Float = runCatching {
        val am = ctx.getSystemService(AudioManager::class.java)
        val s = AudioManager.STREAM_MUSIC
        val spk = AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
        val max = am.getStreamMaxVolume(s)
        val nowDb = am.getStreamVolumeDb(s, am.getStreamVolume(s), spk)
        if (!nowDb.isFinite() || nowDb < -60f) return@runCatching 0f      // muted: stay silent even if raised later
        val refDb = am.getStreamVolumeDb(s, Math.round(max * HISS_SPEAKER_REF_VOL), spk)
        val v = HISS_SPEAKER_REF * Math.pow(10.0, (refDb - nowDb + HISS_SPEAKER_DB) / 20.0).toFloat()
        Log.i("Feedback", "speaker hiss: media ${"%.1f".format(nowDb)} dB -> track volume ${"%.4f".format(v)}")
        v.coerceIn(0f, 1f)
    }.getOrDefault(0.01f)

    private fun headphones(ctx: Context): Boolean = runCatching {
        val types = mutableSetOf(
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_USB_HEADSET,
        )
        if (Build.VERSION.SDK_INT >= 31) types += AudioDeviceInfo.TYPE_BLE_HEADSET
        ctx.getSystemService(AudioManager::class.java)
            .getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { it.type in types }
    }.getOrDefault(false)

    // ---- plumbing ---------------------------------------------------------------------------

    private fun play(pcm: ShortArray, vol: Float, sr: Int) {
        if (!Prefs.sounds.value) return
        val track = buildTrack(pcm.size, sr) ?: return
        try {
            track.write(pcm, 0, pcm.size)
            track.setVolume(vol)
            track.play()
            main.postDelayed({ track.release() }, pcm.size * 1000L / sr + 300)
        } catch (e: Exception) {
            Log.w("Feedback", "sound failed", e)
            track.release()
        }
    }

    /** Media stream, so the "Media" volume slider controls it and it isn't muted by ringer modes. */
    private fun buildTrack(samples: Int, sr: Int): AudioTrack? = try {
        AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sr)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(samples * 2)
            .build()
    } catch (e: Exception) {
        Log.w("Feedback", "AudioTrack failed", e); null
    }

    private fun vibrate(ctx: Context, timings: LongArray, amps: IntArray) {
        try {
            val v: Vibrator = if (Build.VERSION.SDK_INT >= 31)
                ctx.getSystemService(VibratorManager::class.java).defaultVibrator
            else
                @Suppress("DEPRECATION") ctx.getSystemService(Vibrator::class.java)
            // Alarm usage so the haptic still fires in Do Not Disturb at night.
            val aa = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build()
            @Suppress("DEPRECATION")
            v.vibrate(VibrationEffect.createWaveform(timings, amps, -1), aa)
        } catch (e: Exception) {
            Log.w("Feedback", "vibrate failed", e)
        }
    }
}

/** Synthesized REC monitor hiss (the key sounds are recorded clips, see [Feedback]). */
object Synth {
    const val SR = 44100

    /**
     * 2 s seamless loop: high-frequency tape hiss with slow flutter, plus a faint 50/100 Hz
     * capstan-motor hum. Every periodic component has a whole number of cycles in the loop,
     * and the noise tail is cross-faded into the head, so the loop has no click.
     */
    fun hiss(): ShortArray {
        val n = SR * 2
        val xf = SR / 10
        val r = Random(42)
        val noise = FloatArray(n + xf)
        var lp1 = 0f; var lp2 = 0f
        for (i in noise.indices) {
            val w = r.nextFloat() * 2f - 1f
            lp1 += 0.08f * (w - lp1)          // remove rumble -> hiss is mostly highs
            val hp = w - lp1
            lp2 += 0.55f * (hp - lp2)         // soften the very top (~9 kHz)
            noise[i] = lp2
        }
        for (i in 0 until xf) {               // crossfade tail into head
            val a = i.toFloat() / xf
            noise[i] = noise[i] * a + noise[n + i] * (1 - a)
        }
        return ShortArray(n) { i ->
            val t = i.toDouble() / SR
            val flutter = 1f + 0.18f * sin(2 * PI * 0.5 * t).toFloat() + 0.07f * sin(2 * PI * 3.5 * t).toFloat()
            val hum = 0.0022f * sin(2 * PI * 50 * t).toFloat() + 0.0014f * sin(2 * PI * 100 * t).toFloat()
            val v = noise[i] * 0.020f * flutter + hum
            (v * 32767).toInt().toShort()
        }
    }

    /**
     * A detent tick, ~25 ms: a soft (low-passed) noise click, a short woody body around 500 Hz
     * and a little thump. Everything dies away within a few milliseconds, so nothing rings:
     * long high-pitched ringing is what makes a click sound metallic.
     */
    fun detent(): ShortArray {
        val n = SR * 25 / 1000
        val r = Random(7)
        var lp = 0f
        return ShortArray(n) { i ->
            val t = i.toDouble() / SR
            lp += 0.3f * (r.nextFloat() * 2f - 1f - lp)
            val click = lp * exp(-t / 0.0012).toFloat()
            val body = 0.45f * (sin(2 * PI * 480 * t) * exp(-t / 0.0035)).toFloat()
            val thump = 0.35f * (sin(2 * PI * 140 * t) * exp(-t / 0.008)).toFloat()
            val v = (click * 1.1f + body + thump) * 0.7f
            (v.coerceIn(-1f, 1f) * 32767).toInt().toShort()
        }
    }
}

/**
 * Synthesized stand-ins for the recorded key sounds, for builds without the Pixabay clips
 * (they aren't in the public source). Same timing as the recordings, so the haptics still
 * line up; plainer, but clearly a deck.
 */
object SynthKeys {
    private const val SR = 24_000

    private fun buf(ms: Int) = FloatArray(SR * ms / 1000)

    /** A mechanical hit at [atMs]: a noise click, a short body at [hz], and a low thump. */
    private fun FloatArray.hit(atMs: Int, gain: Float, hz: Double = 900.0, decayMs: Double = 4.0, seed: Int = atMs) {
        val r = Random(seed)
        var lp = 0f
        val start = SR * atMs / 1000
        for (i in 0 until minOf(SR / 20, size - start)) {
            val t = i.toDouble() / SR
            lp += 0.35f * (r.nextFloat() * 2f - 1f - lp)
            val click = lp * exp(-t / 0.0015).toFloat()
            val body = 0.5f * (sin(2 * PI * hz * t) * exp(-t / (decayMs / 1000))).toFloat()
            val thump = 0.4f * (sin(2 * PI * 120 * t) * exp(-t / 0.012)).toFloat()
            this[start + i] += gain * (click + body + thump)
        }
    }

    private fun FloatArray.pcm() = ShortArray(size) { (this[it].coerceIn(-1f, 1f) * 30000).toInt().toShort() }

    fun key(variant: Int) = buf(60).apply { hit(0, 0.8f, if (variant == 1) 1100.0 else 950.0, seed = variant) }.pcm()

    /** Fingertip contact, then the latch clacking in (~82 ms). */
    fun rec() = buf(300).apply { hit(0, 0.3f); hit(82, 1f, 700.0, 6.0) }.pcm()

    /** STOP clacks down (~55 ms), the keys release (~185 ms), the mechanism thuds (~280 ms). */
    fun stop() = buf(420).apply { hit(55, 1f, 700.0, 6.0); hit(185, 0.5f, 1000.0); hit(280, 0.8f, 300.0, 10.0) }.pcm()

    /** Key travel (~70 ms), latch (~160 ms), the cassette popping up (~250 ms). */
    fun eject() = buf(420).apply { hit(70, 0.4f); hit(160, 0.6f, 800.0); hit(250, 1f, 400.0, 9.0) }.pcm()

    /** The shell sliding in (a soft scrape), then clunking home (~360 ms). */
    fun insert() = buf(520).apply {
        val r = Random(5)
        var lp = 0f
        for (i in 0 until SR * 300 / 1000) {
            lp += 0.1f * (r.nextFloat() * 2f - 1f - lp)
            this[i] += lp * 0.5f * sin(PI * i / (SR * 0.3)).toFloat()
        }
        hit(10, 0.4f); hit(360, 1f, 450.0, 9.0)
    }.pcm()

    /** One second of motor whirr, looping seamlessly (whole cycles, noise cross-faded). */
    fun wind(): ShortArray {
        val n = SR; val xf = SR / 10
        val r = Random(11)
        var lp = 0f
        val noise = FloatArray(n + xf) { lp += 0.15f * (r.nextFloat() * 2f - 1f - lp); lp }
        for (i in 0 until xf) { val a = i.toFloat() / xf; noise[i] = noise[i] * a + noise[n + i] * (1 - a) }
        return ShortArray(n) { i ->
            val t = i.toDouble() / SR
            val hum = 0.10f * sin(2 * PI * 180 * t).toFloat() + 0.05f * sin(2 * PI * 360 * t).toFloat()
            ((noise[i] * 0.6f + hum).coerceIn(-1f, 1f) * 30000).toInt().toShort()
        }
    }
}
