package com.dic2phone

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Address
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import java.util.Locale
import kotlin.concurrent.thread

/** Where a tape was recorded: one location fix per tape plus a nearby place name. */
object Where {
    private const val TAG = "Where"
    private const val FIX_TIMEOUT_MS = 20_000L
    /** A remembered fix younger than this is good enough. */
    private const val FRESH_MS = 2 * 60_000L

    fun permitted(ctx: Context) =
        ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    fun wanted(ctx: Context) = Prefs.location.value && permitted(ctx)

    /** One fix, delivered on the main thread (null if none could be had). */
    @SuppressLint("MissingPermission")
    fun fix(ctx: Context, done: (Location?) -> Unit) {
        val main = Handler(Looper.getMainLooper())
        if (!permitted(ctx)) { main.post { done(null) }; return }
        val lm = ctx.getSystemService(LocationManager::class.java)
        val last = runCatching {
            lm.getProviders(true).mapNotNull { lm.getLastKnownLocation(it) }.maxByOrNull { it.time }
        }.getOrNull()
        if (last != null && System.currentTimeMillis() - last.time < FRESH_MS) { main.post { done(last) }; return }
        if (Build.VERSION.SDK_INT < 30) { main.post { done(last) }; return }

        val provider = when {
            Build.VERSION.SDK_INT >= 31 && lm.isProviderEnabled(LocationManager.FUSED_PROVIDER) -> LocationManager.FUSED_PROVIDER
            lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            lm.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            else -> { main.post { done(last) }; return }
        }
        val cancel = CancellationSignal()
        var answered = false
        fun answer(l: Location?) { if (!answered) { answered = true; done(l ?: last) } }
        main.postDelayed({ cancel.cancel(); answer(null) }, FIX_TIMEOUT_MS)
        runCatching {
            lm.getCurrentLocation(provider, cancel, ctx.mainExecutor) { l -> answer(l) }
        }.onFailure { Log.w(TAG, "fix", it); main.post { answer(null) } }
    }

    /** A short human place name ("Andrássy út 12, Budapest"), delivered on the main thread. */
    fun placeName(ctx: Context, lat: Double, lon: Double, done: (String?) -> Unit) {
        val main = Handler(Looper.getMainLooper())
        if (!Geocoder.isPresent()) { main.post { done(null) }; return }
        val g = Geocoder(ctx, Locale.getDefault())
        if (Build.VERSION.SDK_INT >= 33) {
            runCatching {
                g.getFromLocation(lat, lon, 1, object : Geocoder.GeocodeListener {
                    override fun onGeocode(list: MutableList<Address>) { main.post { done(list.firstOrNull()?.let(::describe)) } }
                    override fun onError(msg: String?) { Log.w(TAG, "geocode: $msg"); main.post { done(null) } }
                })
            }.onFailure { main.post { done(null) } }
        } else thread(name = "geocode") {
            val a = runCatching { @Suppress("DEPRECATION") g.getFromLocation(lat, lon, 1)?.firstOrNull() }
                .onFailure { Log.w(TAG, "geocode", it) }.getOrNull()
            main.post { done(a?.let(::describe)) }
        }
    }

    private fun describe(a: Address): String {
        val street = a.thoroughfare?.let { s -> a.subThoroughfare?.let { "$s $it" } ?: s }
        val town = a.locality ?: a.subAdminArea ?: a.adminArea
        val parts = listOfNotNull(street ?: a.featureName?.takeIf { it != town }, town, a.countryCode)
        return parts.distinct().joinToString(", ").ifBlank { a.getAddressLine(0) ?: "" }
    }
}
