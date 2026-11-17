package com.dic2phone

import android.os.ParcelFileDescriptor
import android.system.Os
import java.io.ByteArrayOutputStream
import java.io.FileDescriptor
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Writes title / comment / date / place into an .m4a's moov/udta box, the iTunes-style tags
 * (©nam, ©cmt, ©day, ©too) and the QuickTime location (©xyz) that phones, players and
 * computers show.
 *
 * Edited in place without ever moving the audio: only the moov box is rewritten, either where
 * it is (when it's the last box, or there's free space after it) or appended at the end with
 * the old one turned into a 'free' box. The audio (mdat) stays where it is, so chunk offsets
 * stay valid and a long tape costs no more than a short one.
 */
object Mp4Tags {
    class Tags(val title: String, val comment: String, val date: String, val lat: Double?, val lon: Double?)

    fun of(id: String, m: TapeMeta): Tags {
        val start = m.startedAt.takeIf { it > 0 }
        val date = start?.let { SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US).format(Date(it)) }
            ?: id.take(10)
        val comment = buildString {
            if (m.notes.isNotBlank()) append(m.notes.trim())
            fun line(s: String) { if (isNotEmpty()) append('\n'); append(s) }
            if (m.tags.isNotEmpty()) line("Tags: " + m.tags.joinToString(", "))
            if (m.place.isNotBlank()) line("Place: " + m.place)
            if (m.flags.isNotEmpty()) line("Flags: " + m.flags.joinToString(", ") { f ->
                TapeNames.duration(f) + m.note(f).takeIf { it.isNotBlank() }?.let { " ($it)" }.orEmpty()
            })
        }
        return Tags(
            title = m.title.ifBlank { "Dic2Phone ${TapeNames.pretty(id)}" },
            comment = comment, date = date, lat = m.lat, lon = m.lon,
        )
    }

    private class Box(val type: String, val off: Long, val size: Long, val hdr: Int)

    fun write(pfd: ParcelFileDescriptor, t: Tags) {
        val fd = pfd.fileDescriptor
        val fileSize = Os.fstat(fd).st_size
        val boxes = topLevel(fd, fileSize)
        val moov = boxes.firstOrNull { it.type == "moov" } ?: throw IOException("no moov box")
        if (moov.size > 64L * 1024 * 1024 || moov.hdr != 8) throw IOException("unexpected moov")
        val old = ByteArray(moov.size.toInt()).also { readFully(fd, it, moov.off) }
        val new = rebuildMoov(old, t)
        check(sane(new, 8, new.size)) { "built a broken moov" }

        val n = new.size.toLong()
        val i = boxes.indexOf(moov)
        val next = boxes.getOrNull(i + 1)
        val freeAfter = next?.takeIf { (it.type == "free" || it.type == "skip") && it.hdr == 8 }?.size ?: 0L
        val room = moov.size + freeAfter
        when {
            moov.off + moov.size >= fileSize -> {
                writeFully(fd, new, moov.off)
                Os.ftruncate(fd, moov.off + n)
            }
            n == room || n + 8 <= room -> {
                writeFully(fd, new, moov.off)
                if (room > n) writeFully(fd, header(room - n, "free"), moov.off + n)
            }
            else -> {
                // Doesn't fit: put the new moov at the end first, only then retire the old one.
                writeFully(fd, new, fileSize)
                writeFully(fd, "free".toByteArray(Charsets.ISO_8859_1), moov.off + 4)
            }
        }
        runCatching { Os.fsync(fd) }
    }

    private fun topLevel(fd: FileDescriptor, fileSize: Long): List<Box> {
        val out = mutableListOf<Box>()
        var off = 0L
        val h = ByteArray(16)
        while (off + 8 <= fileSize) {
            readFully(fd, h, off, 8)
            var size = u32(h, 0)
            val type = String(h, 4, 4, Charsets.ISO_8859_1)
            var hdr = 8
            if (size == 1L) {
                readFully(fd, h, off + 8, 8)
                size = (u32(h, 0) shl 32) or u32(h, 4)
                hdr = 16
            } else if (size == 0L) size = fileSize - off
            if (size < hdr) throw IOException("bad box at $off")
            out += Box(type, off, size, hdr)
            off += size
        }
        return out
    }

    /** Children of a box body [from, to) as (type, start, size); 32-bit sizes only (moov tree). */
    private fun children(b: ByteArray, from: Int, to: Int): List<Triple<String, Int, Int>> {
        val out = mutableListOf<Triple<String, Int, Int>>()
        var p = from
        while (p + 8 <= to) {
            val size = u32(b, p).toInt()
            if (size < 8 || p + size > to) throw IOException("bad child box")
            out += Triple(String(b, p + 4, 4, Charsets.ISO_8859_1), p, size)
            p += size
        }
        return out
    }

    private fun sane(b: ByteArray, from: Int, to: Int): Boolean =
        runCatching { children(b, from, to).sumOf { it.third } == to - from }.getOrDefault(false)

    private fun rebuildMoov(moov: ByteArray, t: Tags): ByteArray {
        val kids = children(moov, 8, moov.size)
        val udta = kids.firstOrNull { it.first == "udta" }
        val keep = ByteArrayOutputStream()
        if (udta != null) {
            children(moov, udta.second + 8, udta.second + udta.third).forEach { (type, s, size) ->
                val ours = type == "meta" || (type == "©xyz" && t.lat != null)
                if (!ours) keep.write(moov, s, size)
            }
        }
        keep.write(metaBox(t))
        if (t.lat != null && t.lon != null) keep.write(xyzBox(t.lat, t.lon))
        val newUdta = box("udta", keep.toByteArray())

        val body = ByteArrayOutputStream()
        var placed = false
        kids.forEach { (type, s, size) ->
            if (type == "udta") { if (!placed) { body.write(newUdta); placed = true } }
            else body.write(moov, s, size)
        }
        if (!placed) body.write(newUdta)
        return box("moov", body.toByteArray())
    }

    private fun metaBox(t: Tags): ByteArray {
        val hdlr = box(
            "hdlr",
            ByteArray(4) + ByteArray(4) + "mdir".latin() + "appl".latin() + ByteArray(8) + ByteArray(1)
        )
        val items = ByteArrayOutputStream()
        fun item(code: String, value: String) {
            if (value.isBlank()) return
            val data = box("data", byteArrayOf(0, 0, 0, 1) + ByteArray(4) + value.toByteArray(Charsets.UTF_8))
            items.write(box(code, data))
        }
        item("©nam", t.title)
        item("©cmt", t.comment)
        item("©day", t.date)
        item("©too", "Dic2Phone")
        return box("meta", ByteArray(4) + hdlr + box("ilst", items.toByteArray()))
    }

    /** ISO 6709 location, the way Android's own recorder and camera write it. */
    private fun xyzBox(lat: Double, lon: Double): ByteArray {
        val s = "%+08.4f%+09.4f/".format(Locale.US, lat, lon).latin()
        return box("©xyz", byteArrayOf((s.size shr 8).toByte(), s.size.toByte(), 0x15, 0xC7.toByte()) + s)
    }

    private fun String.latin() = toByteArray(Charsets.ISO_8859_1)

    private fun header(size: Long, type: String): ByteArray =
        byteArrayOf((size shr 24).toByte(), (size shr 16).toByte(), (size shr 8).toByte(), size.toByte()) + type.latin()

    private fun box(type: String, body: ByteArray): ByteArray = header(8L + body.size, type) + body

    private fun u32(b: ByteArray, o: Int): Long =
        ((b[o].toLong() and 0xFF) shl 24) or ((b[o + 1].toLong() and 0xFF) shl 16) or
            ((b[o + 2].toLong() and 0xFF) shl 8) or (b[o + 3].toLong() and 0xFF)

    private fun readFully(fd: FileDescriptor, b: ByteArray, pos: Long, len: Int = b.size) {
        var done = 0
        while (done < len) {
            val n = Os.pread(fd, b, done, len - done, pos + done)
            if (n <= 0) throw IOException("short read")
            done += n
        }
    }

    private fun writeFully(fd: FileDescriptor, b: ByteArray, pos: Long) {
        var done = 0
        while (done < b.size) {
            val n = Os.pwrite(fd, b, done, b.size - done, pos + done)
            if (n <= 0) throw IOException("short write")
            done += n
        }
    }
}
