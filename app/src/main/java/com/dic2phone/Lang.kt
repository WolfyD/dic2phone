package com.dic2phone

import android.app.Activity
import android.app.LocaleManager
import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import android.os.Build
import android.os.LocaleList
import androidx.annotation.PluralsRes
import androidx.annotation.StringRes
import java.util.Locale

/**
 * The app's own UI language, independent of the phone's. "" follows the system.
 *
 * Android 13+ keeps the choice itself (per-app language, also settable in system Settings).
 * Before that it's kept in a small private pref and applied by wrapping each activity's,
 * service's and the app's context in [wrap].
 */
object Lang {
    /** Tag to native name. "" = follow the phone. */
    val ALL = listOf(
        "" to "",
        "en" to "English",
        "hu" to "Magyar",
        "de" to "Deutsch",
        "es" to "Español",
        "fr" to "Français",
        "pt-BR" to "Português",
        "ru" to "Русский",
        "zh-CN" to "中文",
    )

    private const val PREFS = "lang"
    private const val KEY = "tag"

    fun current(ctx: Context): String =
        if (Build.VERSION.SDK_INT >= 33) {
            ctx.getSystemService(LocaleManager::class.java).applicationLocales.toLanguageTags()
                .split(',').first().let { t -> ALL.firstOrNull { matches(it.first, t) }?.first ?: t }
        } else {
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, "") ?: ""
        }

    private fun matches(ours: String, tag: String) =
        ours.isNotEmpty() && (ours.equals(tag, true) || ours.substringBefore('-').equals(tag, true))

    fun set(activity: Activity, tag: String) {
        if (Build.VERSION.SDK_INT >= 33) {
            // The system recreates the activities in the new language.
            activity.getSystemService(LocaleManager::class.java).applicationLocales =
                if (tag.isEmpty()) LocaleList.getEmptyLocaleList() else LocaleList.forLanguageTags(tag)
        } else {
            activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, tag).commit()
            L.reset()
            activity.recreate()
        }
    }

    /** API < 33: [base] with the chosen language applied. Pass-through otherwise. */
    fun wrap(base: Context): Context {
        if (Build.VERSION.SDK_INT >= 33) return base
        val tag = base.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, "") ?: ""
        if (tag.isEmpty()) return base
        val loc = Locale.forLanguageTag(tag)
        Locale.setDefault(loc)
        val cfg = Configuration(base.resources.configuration)
        cfg.setLocales(LocaleList(loc))
        return base.createConfigurationContext(cfg)
    }
}

/**
 * Strings for code that runs outside the UI (notifications, services, toasts from helpers):
 * always in the app's current language.
 */
object L {
    lateinit var app: Context
    private var cached: Pair<LocaleList, Resources>? = null

    fun reset() { cached = null }

    private fun res(): Resources {
        val want = if (Build.VERSION.SDK_INT >= 33) {
            app.getSystemService(LocaleManager::class.java).applicationLocales.takeIf { !it.isEmpty }
                ?: Resources.getSystem().configuration.locales
        } else {
            Lang.wrap(app).resources.configuration.locales
        }
        cached?.let { (l, r) -> if (l == want) return r }
        val cfg = Configuration(app.resources.configuration).apply { setLocales(want) }
        return app.createConfigurationContext(cfg).resources.also { cached = want to it }
    }

    /** The app's current UI locale, for dates and numbers. */
    fun locale(): Locale = res().configuration.locales[0]

    fun s(@StringRes id: Int, vararg args: Any?): String =
        if (args.isEmpty()) res().getString(id) else res().getString(id, *args)
    fun p(@PluralsRes id: Int, n: Int, vararg args: Any?): String =
        res().getQuantityString(id, n, *(if (args.isEmpty()) arrayOf<Any?>(n) else args))
}
