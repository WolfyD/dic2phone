package com.dic2phone

import android.content.Intent
import android.os.Bundle
import android.view.KeyEvent
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.clickable
import com.dic2phone.ui.ThemedSystemBars
import com.dic2phone.ui.deckBackground
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.dic2phone.ui.BrandPlate
import com.dic2phone.ui.CassetteView
import com.dic2phone.ui.Deck
import com.dic2phone.ui.Led
import com.dic2phone.ui.Mono
import com.dic2phone.ui.VuMeter
import com.dic2phone.ui.hasMic
import com.dic2phone.ui.rememberElapsed

/**
 * One-shot recorder. Starts recording as soon as it opens (works over the lock screen).
 * Stops on: tap anywhere, any volume key, back, or leaving the screen (e.g. power button).
 * Launched again while recording (tile / shortcut / side key) -> stops.
 */
class QuickRecordActivity : ComponentActivity() {
    private var stopping = false

    override fun attachBaseContext(base: android.content.Context) {
        super.attachBaseContext(Lang.wrap(base))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        enableEdgeToEdge()

        if (!hasMic(this)) {
            startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            finish(); return
        }
        if (savedInstanceState == null) {
            if (Recorder.state.value.recording) { stopAndFinish(); return }
            RecorderService.start(this, "quick:${intent?.action ?: "?"}")
        }

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() = stopAndFinish()
        })

        setContent {
            val rec by Recorder.state.collectAsStateWithLifecycle()
            val elapsed = rememberElapsed(rec)
            ThemedSystemBars()
            Column(
                Modifier
                    .fillMaxSize()
                    .deckBackground()
                    .clickable(remember { MutableInteractionSource() }, indication = null) { stopAndFinish() }
                    .safeDrawingPadding()
                    .padding(20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterVertically)
            ) {
                BrandPlate()
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Led(rec.recording, size = 20.dp)
                    Text(
                        L.s(R.string.quick_rec_time, TapeNames.duration(elapsed)),
                        color = if (rec.recording) Deck.led else Deck.dim,
                        fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 34.sp
                    )
                }
                CassetteView(
                    label = L.s(R.string.quick_title),
                    sub = L.s(R.string.quick_sub),
                    spinning = rec.tapeMoving,
                    progress = (elapsed / 600_000f).coerceAtMost(1f),
                    modifier = Modifier.fillMaxWidth()
                )
                VuMeter(if (rec.recording) rec.level else 0f, Modifier.fillMaxWidth(.8f))
                Text(
                    rec.error ?: L.s(R.string.quick_help),
                    color = if (rec.error != null) Deck.orange else Deck.dim,
                    fontFamily = Mono, fontSize = 13.sp, textAlign = TextAlign.Center
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        stopAndFinish()
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            stopAndFinish(); return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onStop() {
        super.onStop()
        if (!isChangingConfigurations) stopAndFinish()
    }

    private fun stopAndFinish() {
        if (stopping) return
        stopping = true
        RecorderService.stop()
        finish()
    }
}
