package com.dic2phone

import android.content.ContentValues
import android.content.Context
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Everything known about one tape: facts the recorder wrote down, what the user wrote on the
 * label, where it was recorded, and the flagged moments.
 */
data class TapeMeta(
    // ---- yours
    val title: String = "",
    val notes: String = "",
    val tags: List<String> = emptyList(),
    // ---- recording facts (filled in by the recorder)
    val startedAt: Long = 0L,        // wall clock, ms
    val endedAt: Long = 0L,
    val durationMs: Long = 0L,
    val sizeBytes: Long = 0L,
    val format: String = "",
    val peakDb: Float? = null,       // dBFS
    val avgDb: Float? = null,        // dBFS, RMS over the tape
    val source: String = "",         // what started it (rec-key, vol-down, tile, ...)
    val device: String = "",
    val latched: Boolean = false,
    val vox: Boolean = false,
    val cuts: Int = 0,               // silences skipped by noise-activated recording
    val skippedMs: Long = 0L,        // how much silence that removed
    val part: Int = 0,               // 1, 2, ... when a long session was split into hour tapes
    // ---- place
    val lat: Double? = null,
    val lon: Double? = null,
    val accuracyM: Float? = null,
    val place: String = "",
    // ---- flagged moments, ms from the start of the tape, sorted
    val flags: List<Long> = emptyList(),
    /** A note on a flag, keyed by the flag's position. */
    val flagNotes: Map<Long, String> = emptyMap(),
) {
    fun note(flag: Long): String = flagNotes[flag].orEmpty()
    val hasPlace get() = lat != null && lon != null

    fun toJson(): JSONObject = JSONObject().apply {
        put("v", 1)
        if (title.isNotEmpty()) put("title", title)
        if (notes.isNotEmpty()) put("notes", notes)
        if (tags.isNotEmpty()) put("tags", JSONArray(tags))
        if (startedAt > 0) put("start", startedAt)
        if (endedAt > 0) put("end", endedAt)
        if (durationMs > 0) put("dur", durationMs)
        if (sizeBytes > 0) put("size", sizeBytes)
        if (format.isNotEmpty()) put("format", format)
        peakDb?.let { put("peak", it.toDouble()) }
        avgDb?.let { put("avg", it.toDouble()) }
        if (source.isNotEmpty()) put("source", source)
        if (device.isNotEmpty()) put("device", device)
        if (latched) put("latched", true)
        if (vox) put("vox", true)
        if (cuts > 0) put("cuts", cuts)
        if (skippedMs > 0) put("skipped", skippedMs)
        if (part > 0) put("part", part)
        lat?.let { put("lat", it) }
        lon?.let { put("lon", it) }
        accuracyM?.let { put("acc", it.toDouble()) }
        if (place.isNotEmpty()) put("place", place)
        if (flags.isNotEmpty()) put("flags", JSONArray(flags))
        // Notes only for flags that are still there (unflagging drops the note too).
        val notes = flagNotes.filter { (k, v) -> k in flags && v.isNotBlank() }
        if (notes.isNotEmpty()) put("flagNotes", JSONObject().apply { notes.forEach { (k, v) -> put(k.toString(), v) } })
    }

    companion object {
        fun fromJson(o: JSONObject) = TapeMeta(
            title = o.optString("title"),
            notes = o.optString("notes"),
            tags = o.optJSONArray("tags")?.let { a -> List(a.length()) { a.getString(it) } }.orEmpty(),
            startedAt = o.optLong("start"),
            endedAt = o.optLong("end"),
            durationMs = o.optLong("dur"),
            sizeBytes = o.optLong("size"),
            format = o.optString("format"),
            peakDb = if (o.has("peak")) o.getDouble("peak").toFloat() else null,
            avgDb = if (o.has("avg")) o.getDouble("avg").toFloat() else null,
            source = o.optString("source"),
            device = o.optString("device"),
            latched = o.optBoolean("latched"),
            vox = o.optBoolean("vox"),
            cuts = o.optInt("cuts"),
            skippedMs = o.optLong("skipped"),
            part = o.optInt("part"),
            lat = if (o.has("lat")) o.getDouble("lat") else null,
            lon = if (o.has("lon")) o.getDouble("lon") else null,
            accuracyM = if (o.has("acc")) o.getDouble("acc").toFloat() else null,
            place = o.optString("place"),
            flags = o.optJSONArray("flags")?.let { a -> List(a.length()) { a.getLong(it) } }.orEmpty().sorted(),
            flagNotes = o.optJSONObject("flagNotes")?.let { n ->
                n.keys().asSequence().mapNotNull { k -> k.toLongOrNull()?.let { it to n.optString(k) } }.toMap()
            }.orEmpty(),
        )

        fun parse(s: String?): TapeMeta? =
            s?.let { runCatching { fromJson(JSONObject(it)) }.onFailure { e -> Log.w("TapeMeta", "bad meta", e) }.getOrNull() }

        val DEVICE: String
            get() = listOf(android.os.Build.MANUFACTURER.replaceFirstChar { it.uppercase() }, android.os.Build.MODEL)
                .distinct().joinToString(" ") + " · Android ${android.os.Build.VERSION.RELEASE}"

        const val FORMAT = "AAC-LC · 44.1 kHz · mono · 96 kbps"
        const val TAGS_MAX = 12
    }
}

/**
 * Where metadata lives: a small JSON file per tape in app storage, keyed by the tape's file
 * name (like captions, so it follows a tape from the deck to the shelf for free). Vault tapes
 * keep theirs sealed in the vault. Title, notes, date and place are also written into the
 * .m4a itself, so they travel with the file when it's sent or copied off the phone.
 */
object MetaStore {
    private const val TAG = "MetaStore"

    fun dir(ctx: Context) = File(ctx.filesDir, "meta").apply { mkdirs() }
    fun file(ctx: Context, id: String) = File(dir(ctx), id.substringBeforeLast('.') + ".json")

    fun loadPlain(ctx: Context, id: String): TapeMeta? =
        file(ctx, id).takeIf { it.exists() }?.let { f -> TapeMeta.parse(runCatching { f.readText() }.getOrNull()) }

    /** Never null: tapes from before metadata existed get an empty record. */
    fun load(ctx: Context, t: Tape): TapeMeta =
        (if (t.vault != null) TapeMeta.parse(Vault.readMeta(ctx, t.vault)) else loadPlain(ctx, t.id)) ?: TapeMeta()

    fun writePlain(ctx: Context, id: String, m: TapeMeta) {
        val f = file(ctx, id)
        val tmp = File(f.parentFile, f.name + ".tmp")
        FileOutputStream(tmp).use { it.write(m.toJson().toString().toByteArray()); it.fd.sync() }
        f.replaceWith(tmp)
    }

    fun delete(ctx: Context, id: String) { file(ctx, id).delete() }

    /**
     * Saves [m] for [t] and (for deck and shelf tapes) re-tags the audio file in the background.
     * Call off the main thread.
     */
    fun save(ctx: Context, t: Tape, m: TapeMeta) {
        val app = ctx.applicationContext
        if (t.vault != null) Vault.writeMeta(app, t.vault, m.toJson().toString())
        else {
            writePlain(app, t.id, m)
            retag(app, t, m)
        }
        TapeStore.bump()
    }

    fun update(ctx: Context, t: Tape, change: (TapeMeta) -> TapeMeta) = save(ctx, t, change(load(ctx, t)))

    // ---- Tags inside the file ------------------------------------------------------------

    private val tagger = Executors.newSingleThreadExecutor { r -> Thread(r, "tagger") }

    /** Writes [m] into [t]'s audio file (deck or shelf) on the tagger thread. */
    fun retag(ctx: Context, t: Tape, m: TapeMeta) {
        val app = ctx.applicationContext
        tagger.execute {
            synchronized(TapeStore.io) {
                runCatching {
                    val tags = Mp4Tags.of(t.id, m)
                    if (t.file != null) {
                        if (!t.file.exists()) return@runCatching
                        ParcelFileDescriptor.open(t.file, ParcelFileDescriptor.MODE_READ_WRITE).use { Mp4Tags.write(it, tags) }
                    } else {
                        app.contentResolver.openFileDescriptor(t.uri, "rw")?.use { Mp4Tags.write(it, tags) }
                        app.contentResolver.update(t.uri, ContentValues().apply {
                            put(MediaStore.Audio.Media.TITLE, tags.title)
                        }, null, null)
                    }
                }.onFailure { Log.w(TAG, "tag ${t.id}", it) }
            }
        }
    }

    /** Tags a plain copy that's about to be sent (vault / LO-FI copies), synchronously. */
    fun tagCopy(f: File, id: String, m: TapeMeta) {
        runCatching {
            ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_WRITE).use { Mp4Tags.write(it, Mp4Tags.of(id, m)) }
        }.onFailure { Log.w(TAG, "tag copy $id", it) }
    }

    // ---- Formatting helpers ----------------------------------------------------------------

    fun clock(ms: Long): String = L.locale().let { SimpleDateFormat("dd MMM yyyy  HH:mm:ss", it).format(Date(ms)).uppercase(it) }

    fun size(b: Long): String = when {
        b >= 1_000_000 -> "%.1f MB".format(b / 1e6)
        b >= 1_000 -> "%d kB".format(b / 1000)
        else -> "$b B"
    }

    fun coords(lat: Double, lon: Double) =
        "%.5f° %s, %.5f° %s".format(Locale.US, kotlin.math.abs(lat), if (lat >= 0) "N" else "S", kotlin.math.abs(lon), if (lon >= 0) "E" else "W")

    fun source(s: String): String = when {
        s.startsWith("rec-key") -> L.s(R.string.src_rec_key)
        s.startsWith("vol-down") -> L.s(R.string.src_vol)
        s.startsWith("headset") -> L.s(R.string.src_headset)
        s.startsWith("quick:android.intent.action.ASSIST") -> L.s(R.string.src_assist)
        s.startsWith("quick:") -> L.s(R.string.src_quick)
        s.startsWith("widget") -> L.s(R.string.src_widget)
        s.startsWith("tile") -> L.s(R.string.src_tile)
        s.startsWith("split") -> L.s(R.string.src_split)
        s.startsWith("recovered") -> L.s(R.string.src_recovered)
        else -> s
    }
}
