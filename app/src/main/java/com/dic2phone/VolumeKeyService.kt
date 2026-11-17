package com.dic2phone

import android.accessibilityservice.AccessibilityService
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

/**
 * Gesture: tap Volume Down, then press and HOLD it again within [GAP_MS] -> records while held.
 * Tap, tap, tap instead (the second press short, the third quick) -> recording LOCKS on and
 * keeps going without holding anything; one more press of Volume Down stops it. While locked,
 * Volume Down doesn't change the volume.
 *
 * Because we must decide on the first press whether it's the start of the gesture, every
 * Volume Down press is consumed and re-applied to the volume if no gesture follows:
 *  - single short tap  -> volume lowered after GAP_MS
 *  - first press held  -> behaves like a normal held volume key (repeats)
 * Volume Up and all other keys pass through untouched. During calls we stay out of the way.
 */
class VolumeKeyService : AccessibilityService() {

    private enum class S { IDLE, FIRST_DOWN, WAIT_SECOND, RECORDING, WAIT_THIRD, SWALLOW, PASSTHRU_HOLD }

    private companion object {
        const val TAG = "VolumeKeyService"
        const val TAP_MAX_MS = 350L   // first press must be shorter than this to count as a tap
        const val GAP_MS = 350L       // window for the second press
        const val REPEAT_MS = 120L
        const val HOLD_MS = 800L      // headset button held this long toggles REC
    }

    private val h = Handler(Looper.getMainLooper())
    private var s = S.IDLE
    private var secondDownAt = 0L
    private lateinit var audio: AudioManager

    private val singleTapTimeout = Runnable {
        if (s == S.WAIT_SECOND) { s = S.IDLE; lowerVolume() }
    }
    /** Tap-tap and no third tap: it was just a very short hold. */
    private val thirdTapTimeout = Runnable {
        if (s == S.WAIT_THIRD) { s = S.IDLE; RecorderService.stop() }
    }
    private val holdRepeat = object : Runnable {
        override fun run() {
            if (s == S.FIRST_DOWN) s = S.PASSTHRU_HOLD
            if (s == S.PASSTHRU_HOLD) { lowerVolume(); h.postDelayed(this, REPEAT_MS) }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        audio = getSystemService(AudioManager::class.java)
        Log.i(TAG, "connected")
    }

    // ---- Headset button: hold = lock REC on / stop; a press while recording = flag. ----------
    private var hsDown = false
    private var hsHeld = false
    private val hsHold = Runnable {
        hsHeld = true
        if (Recorder.state.value.recording) RecorderService.stop()
        else RecorderService.start(this, "headset", latched = true)
    }

    private fun headsetKey(e: KeyEvent): Boolean {
        if (!Prefs.headset.value) return false
        val rec = Recorder.state.value.recording
        if (!hsDown && !rec && audio.mode != AudioManager.MODE_NORMAL) return false // calls keep their button
        when (e.action) {
            KeyEvent.ACTION_DOWN -> {
                if (e.repeatCount == 0) {
                    hsDown = true; hsHeld = false
                    h.postDelayed(hsHold, HOLD_MS)
                }
            }
            KeyEvent.ACTION_UP -> {
                if (!hsDown) return false
                hsDown = false
                h.removeCallbacks(hsHold)
                if (!hsHeld) {
                    if (rec) RecorderService.flag()
                    else {
                        // Just a press: hand it on to the music / podcast app as usual.
                        audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, e.keyCode))
                        audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, e.keyCode))
                    }
                }
                hsHeld = false
            }
        }
        return true
    }

    override fun onKeyEvent(e: KeyEvent): Boolean {
        if (e.keyCode == KeyEvent.KEYCODE_HEADSETHOOK || e.keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE) return headsetKey(e)
        if (e.keyCode != KeyEvent.KEYCODE_VOLUME_DOWN) return false
        val locked = Recorder.state.value.run { recording && latched }
        if (s == S.IDLE && !locked && audio.mode != AudioManager.MODE_NORMAL) return false // in a call / ringing

        when (e.action) {
            KeyEvent.ACTION_DOWN -> {
                if (e.repeatCount > 0) return true // we drive repeats ourselves
                when (s) {
                    S.IDLE -> {
                        if (locked) {
                            // Locked recording: one press stops it.
                            s = S.SWALLOW
                            RecorderService.stop()
                        } else {
                            s = S.FIRST_DOWN
                            h.postDelayed(holdRepeat, TAP_MAX_MS)
                        }
                    }
                    S.WAIT_SECOND -> {
                        h.removeCallbacks(singleTapTimeout)
                        s = S.RECORDING
                        secondDownAt = e.eventTime
                        RecorderService.start(this, "vol-down")
                    }
                    S.WAIT_THIRD -> {
                        h.removeCallbacks(thirdTapTimeout)
                        s = S.SWALLOW
                        RecorderService.latch()
                    }
                    else -> {}
                }
                return true
            }
            KeyEvent.ACTION_UP -> {
                when (s) {
                    S.FIRST_DOWN -> {
                        h.removeCallbacks(holdRepeat)
                        s = S.WAIT_SECOND
                        h.postDelayed(singleTapTimeout, GAP_MS)
                    }
                    S.RECORDING -> {
                        if (e.eventTime - secondDownAt < TAP_MAX_MS) {
                            // A tap, not a hold: a third tap now locks it on.
                            s = S.WAIT_THIRD
                            h.postDelayed(thirdTapTimeout, GAP_MS)
                        } else {
                            s = S.IDLE
                            RecorderService.stop()
                        }
                    }
                    S.SWALLOW -> s = S.IDLE
                    S.PASSTHRU_HOLD -> {
                        h.removeCallbacks(holdRepeat)
                        s = S.IDLE
                    }
                    else -> {}
                }
                return true
            }
        }
        return false
    }

    private fun lowerVolume() {
        audio.adjustSuggestedStreamVolume(
            AudioManager.ADJUST_LOWER, AudioManager.USE_DEFAULT_STREAM_TYPE, AudioManager.FLAG_SHOW_UI
        )
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {
        if (s == S.RECORDING || s == S.WAIT_THIRD) RecorderService.stop()
        h.removeCallbacksAndMessages(null)
        s = S.IDLE
        hsDown = false; hsHeld = false
    }
}
