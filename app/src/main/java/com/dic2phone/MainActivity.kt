package com.dic2phone

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.dic2phone.ui.DeckScreen
import com.dic2phone.ui.Screen
import com.dic2phone.ui.SearchScreen
import com.dic2phone.ui.SetupScreen
import com.dic2phone.ui.Shelf
import com.dic2phone.ui.TapeListScreen
import com.dic2phone.ui.ThemedSystemBars
import com.dic2phone.ui.deckBackground

class MainActivity : ComponentActivity() {
    override fun attachBaseContext(base: android.content.Context) {
        super.attachBaseContext(Lang.wrap(base))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            var screen by rememberSaveable { mutableStateOf(Screen.DECK) }
            /** Where SEARCH goes back to. */
            var searchFrom by rememberSaveable { mutableStateOf(Screen.DECK) }
            fun back() {
                screen = when (screen) {
                    Screen.VAULT -> Screen.SHELF
                    Screen.SEARCH -> searchFrom
                    else -> Screen.DECK
                }
            }
            fun go(s: Screen) {
                if (s == Screen.SEARCH && screen != Screen.SEARCH) searchFrom = screen
                screen = s
            }
            BackHandler(screen != Screen.DECK) { back() }
            ThemedSystemBars()
            Box(Modifier.fillMaxSize().deckBackground()) {
                when (screen) {
                    Screen.DECK -> DeckScreen { go(it) }
                    Screen.TAPES -> TapeListScreen(Shelf.DECK, ::back, ::go)
                    Screen.LOAD -> TapeListScreen(Shelf.DECK, ::back, ::go, loadMode = true)
                    Screen.SHELF -> TapeListScreen(Shelf.SHELF, ::back, ::go)
                    Screen.VAULT -> TapeListScreen(Shelf.VAULT, ::back, ::go)
                    Screen.SEARCH -> SearchScreen(::back)
                    Screen.SETUP -> SetupScreen { screen = Screen.DECK }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        Notifs.clearNewTapes(this)
        TapeStore.bump()
    }

    override fun onStop() {
        super.onStop()
        if (!isChangingConfigurations) {
            Player.stop()
            // Leaving the app (home, another app, screen off) always locks the vault.
            Vault.lock()
        }
    }
}
