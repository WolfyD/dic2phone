package com.dic2phone

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.util.Log

/**
 * The microphones the phone offers (built-in ones, a wired headset, USB, Bluetooth), for
 * Setup → REC → MICROPHONE. Device ids change on every plug-in, so a choice is remembered by
 * kind + name; if that mic isn't there when recording starts, the phone's default is used.
 */
object Mics {
    class Mic(val key: String, val label: String, val info: AudioDeviceInfo)

    private fun isBt(type: Int) = type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
        (Build.VERSION.SDK_INT >= 31 && type == AudioDeviceInfo.TYPE_BLE_HEADSET)

    private val wanted = setOf(
        AudioDeviceInfo.TYPE_BUILTIN_MIC, AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
    ) + (if (Build.VERSION.SDK_INT >= 31) setOf(AudioDeviceInfo.TYPE_BLE_HEADSET) else emptySet())

    fun list(ctx: Context): List<Mic> {
        val am = ctx.getSystemService(AudioManager::class.java)
        return am.getDevices(AudioManager.GET_DEVICES_INPUTS)
            .filter { it.type in wanted && (!isBt(it.type) || Build.VERSION.SDK_INT >= 31) }
            .map { d ->
                val name = d.productName?.toString().orEmpty().trim()
                val where = d.address.orEmpty().trim()
                when (d.type) {
                    AudioDeviceInfo.TYPE_BUILTIN_MIC ->
                        Mic("builtin:$where", L.s(R.string.mic_phone) + if (where.isNotEmpty() && where.length <= 12) " · ${where.uppercase()}" else "", d)
                    AudioDeviceInfo.TYPE_WIRED_HEADSET -> Mic("wired:", L.s(R.string.mic_headset), d)
                    AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET ->
                        Mic("usb:$name", "USB · ${name.uppercase().ifEmpty { "MIC" }}", d)
                    else -> Mic("bt:$name", "BT · ${name.uppercase().ifEmpty { L.s(R.string.mic_headset) }}", d)
                }
            }
            .distinctBy { it.key }
    }

    fun find(ctx: Context, key: String): AudioDeviceInfo? =
        if (key.isEmpty()) null else list(ctx).firstOrNull { it.key == key }?.info

    /**
     * Bluetooth mics only send sound while the phone holds a call-style link to them, so ask
     * for one. Returns true if it must be released with [releaseBt] afterwards.
     */
    fun routeBt(ctx: Context, d: AudioDeviceInfo): Boolean {
        if (!isBt(d.type) || Build.VERSION.SDK_INT < 31) return false
        val am = ctx.getSystemService(AudioManager::class.java)
        val out = am.availableCommunicationDevices.firstOrNull { it.address == d.address && isBt(it.type) }
            ?: am.availableCommunicationDevices.firstOrNull { isBt(it.type) }
            ?: return false
        return runCatching { am.setCommunicationDevice(out) }.onFailure { Log.w("Mics", "bt route", it) }.getOrDefault(false)
    }

    fun releaseBt(ctx: Context) {
        if (Build.VERSION.SDK_INT >= 31) runCatching { ctx.getSystemService(AudioManager::class.java).clearCommunicationDevice() }
    }
}
