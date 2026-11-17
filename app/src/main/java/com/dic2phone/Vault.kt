package com.dic2phone

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.media.MediaDataSource
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.Closeable
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.io.RandomAccessFile
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlin.concurrent.thread

/**
 * The vault: a locked compartment of the shelf. Tapes in it live in app-private storage,
 * encrypted with AES-256-GCM. The data key is itself encrypted by an Android Keystore key that
 * only works for 30 s after the user proves it's them (fingerprint or screen-lock PIN/pattern).
 * While unlocked the data key is held in memory; locking forgets it.
 *
 * Files are sealed in 64 KiB GCM chunks so they can be played (random access) straight from
 * the encrypted file through a [MediaDataSource]: no plaintext ever touches the disk, except
 * copies the user explicitly sends (cache, wiped shortly after).
 */
object Vault {
    private const val TAG = "Vault"
    private const val ALIAS = "dic2phone.vault"
    private val rng = SecureRandom()

    @Volatile private var key: SecretKey? = null
    private var entries: MutableList<Entry>? = null

    private val _open = MutableStateFlow(false)
    val open: StateFlow<Boolean> = _open
    val isOpen get() = _open.value

    class Entry(val id: String, val file: String, val durationMs: Long, val size: Long, val added: Long)

    sealed class Unlock {
        data object Ok : Unlock()
        data object Cancelled : Unlock()
        data object NoScreenLock : Unlock()
        /** The Keystore key is gone (screen lock removed / reset): the vault can't be opened again. */
        data object Lost : Unlock()
        data class Failed(val msg: String) : Unlock()
    }

    fun dir(ctx: Context) = File(ctx.filesDir, "vault").apply { mkdirs() }
    private fun keyFile(ctx: Context) = File(dir(ctx), "key")
    private fun indexFile(ctx: Context) = File(dir(ctx), "index")
    fun tapeFile(ctx: Context, name: String) = File(dir(ctx), "$name.d2pv")
    fun captionFile(ctx: Context, name: String) = File(dir(ctx), "$name.cc")
    fun metaFile(ctx: Context, name: String) = File(dir(ctx), "$name.meta")
    /** Decrypted copies the user chose to send; wiped a few minutes after locking. */
    fun sendDir(ctx: Context) = File(ctx.cacheDir, "vault_send")

    fun exists(ctx: Context) = keyFile(ctx).exists()
    fun count(ctx: Context) = entries?.size
    fun deviceSecure(ctx: Context) = ctx.getSystemService(KeyguardManager::class.java).isDeviceSecure

    /** The data key for a job that must outlive a lock (e.g. a caption being written). */
    internal fun currentKey(): SecretKey? = key

    // ---- Lock / unlock ---------------------------------------------------------------------

    fun unlock(activity: Activity, onResult: (Unlock) -> Unit) {
        if (isOpen) { onResult(Unlock.Ok); return }
        if (!deviceSecure(activity)) { onResult(Unlock.NoScreenLock); return }
        val main = Handler(Looper.getMainLooper())
        val b = BiometricPrompt.Builder(activity)
            .setTitle(L.s(R.string.vault_prompt_title))
            .setSubtitle(L.s(R.string.vault_prompt_sub))
        if (Build.VERSION.SDK_INT >= 30) {
            b.setAllowedAuthenticators(
                BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL
            )
        } else {
            @Suppress("DEPRECATION") b.setDeviceCredentialAllowed(true)
        }
        b.build().authenticate(CancellationSignal(), activity.mainExecutor, object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                val app = activity.applicationContext
                thread(name = "vault-open") {
                    val r = runCatching { openWithKeystore(app); Unlock.Ok }.getOrElse { e ->
                        Log.e(TAG, "open", e)
                        if (e is KeyPermanentlyInvalidatedException || e is LostException) Unlock.Lost
                        else Unlock.Failed(e.message ?: e.javaClass.simpleName)
                    }
                    main.post { onResult(r) }
                }
            }

            override fun onAuthenticationError(code: Int, msg: CharSequence) {
                onResult(
                    if (code == BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED || code == BiometricPrompt.BIOMETRIC_ERROR_CANCELED)
                        Unlock.Cancelled else Unlock.Failed(msg.toString())
                )
            }
        })
    }

    private class LostException : Exception("vault key lost")

    private fun openWithKeystore(ctx: Context) {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val kf = keyFile(ctx)
        val dk: ByteArray
        if (!kf.exists()) {
            // First use: make the Keystore key and a fresh data key wrapped by it.
            if (ks.containsAlias(ALIAS)) ks.deleteEntry(ALIAS)
            val master = generateMaster()
            dk = ByteArray(32).also(rng::nextBytes)
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.ENCRYPT_MODE, master)
            val wrapped = c.iv + c.doFinal(dk)
            writeAtomic(kf, wrapped)
            synchronized(this) { entries = mutableListOf() }
        } else {
            val master = ks.getKey(ALIAS, null) as? SecretKey ?: throw LostException()
            val b = kf.readBytes()
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE, master, GCMParameterSpec(128, b, 0, 12))
            dk = c.doFinal(b, 12, b.size - 12)
        }
        val k = SecretKeySpec(dk, "AES")
        synchronized(this) {
            key = k
            entries = loadIndex(ctx, k)
        }
        _open.value = true
        sendDir(ctx).deleteRecursively()
        TapeStore.bump()
    }

    private fun generateMaster(): SecretKey {
        val spec = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(false)
            .apply {
                if (Build.VERSION.SDK_INT >= 30) setUserAuthenticationParameters(
                    30, KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL
                ) else @Suppress("DEPRECATION") setUserAuthenticationValidityDurationSeconds(30)
            }
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            .apply { init(spec) }.generateKey()
    }

    private val wipe = Runnable { sendDir(Prefs.app).deleteRecursively() }

    fun lock() {
        if (!isOpen && key == null) return
        if (Player.playingId.value != null && Player.playingVault) Player.stop()
        if (Player.loaded.value?.vault != null) Player.eject()
        synchronized(this) { key = null; entries = null }
        titles.clear()
        _open.value = false
        // Sent copies: give the receiving app a few minutes to read them, then wipe.
        Handler(Looper.getMainLooper()).apply { removeCallbacks(wipe); postDelayed(wipe, 10 * 60_000L) }
        TapeStore.bump()
    }

    /** Throws away the vault entirely (only offered when the key is lost). */
    fun reset(ctx: Context) {
        lock()
        dir(ctx).deleteRecursively()
        runCatching { KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(ALIAS) }
        TapeStore.bump()
    }

    // ---- Index -------------------------------------------------------------------------------

    private fun loadIndex(ctx: Context, k: SecretKey): MutableList<Entry> {
        val f = indexFile(ctx)
        if (!f.exists()) return mutableListOf()
        val b = f.readBytes()
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, k, GCMParameterSpec(128, b, 0, 12))
        c.updateAAD("index".toByteArray())
        val a = JSONArray(String(c.doFinal(b, 12, b.size - 12)))
        return MutableList(a.length()) { i ->
            val o = a.getJSONObject(i)
            Entry(o.getString("id"), o.getString("f"), o.getLong("dur"), o.getLong("size"), o.optLong("added"))
        }
    }

    private fun saveIndex(ctx: Context) {
        val k = key ?: return
        val list = entries ?: return
        val a = JSONArray()
        list.forEach {
            a.put(JSONObject().put("id", it.id).put("f", it.file).put("dur", it.durationMs).put("size", it.size).put("added", it.added))
        }
        val iv = ByteArray(12).also(rng::nextBytes)
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, k, GCMParameterSpec(128, iv))
        c.updateAAD("index".toByteArray())
        writeAtomic(indexFile(ctx), iv + c.doFinal(a.toString().toByteArray()))
    }

    private fun writeAtomic(f: File, bytes: ByteArray) {
        val tmp = File(f.parentFile, f.name + ".tmp")
        FileOutputStream(tmp).use { it.write(bytes); it.fd.sync() }
        f.replaceWith(tmp)
    }

    // ---- Tapes -------------------------------------------------------------------------------

    fun list(ctx: Context): List<Tape> {
        val es = synchronized(this) { entries?.toList() } ?: return emptyList()
        return es.sortedByDescending { it.id }.map { e ->
            Tape(
                id = e.id, uri = Uri.parse("vault:${e.file}"), file = null,
                durationMs = e.durationMs, sizeBytes = e.size, isNew = false,
                vault = e.file, cc = captionFile(ctx, e.file).exists(),
                title = titles.getOrPut(e.file) { TapeMeta.parse(readMeta(ctx, e.file))?.title.orEmpty() },
            )
        }
    }

    /** Titles of vault tapes (decrypting every meta file on each list would be wasteful). */
    private val titles = java.util.concurrent.ConcurrentHashMap<String, String>()

    private fun newName(): String =
        ByteArray(12).also(rng::nextBytes).joinToString("") { "%02x".format(it) }

    class LockResult(val locked: Int, val leftBehind: Int)

    /** Seals deck/shelf tapes into the vault and removes the originals. Vault must be open. */
    fun lockAway(ctx: Context, tapes: Collection<Tape>): LockResult {
        val k = key ?: return LockResult(0, 0)
        var locked = 0
        var left = 0
        for (t in tapes) {
            if (t.vault != null) continue
            if (Player.playingId.value == t.id) Player.stop()
            val name = newName()
            val out = tapeFile(ctx, name)
            val tmp = File(out.parentFile, "$name.part")
            try {
                ctx.contentResolver.openInputStream(t.uri)!!.use { inp ->
                    SealedOut(FileOutputStream(tmp), k).use { inp.copyTo(it, 64 * 1024) }
                }
                if (!tmp.renameTo(out)) throw IllegalStateException("rename failed")
                Captions.file(ctx, t.id).takeIf { it.exists() }?.let { cc ->
                    SealedOut(FileOutputStream(captionFile(ctx, name)), k).use { o -> cc.inputStream().use { it.copyTo(o) } }
                }
                MetaStore.loadPlain(ctx, t.id)?.let { m ->
                    SealedOut(FileOutputStream(metaFile(ctx, name)), k).use { it.write(m.toJson().toString().toByteArray()) }
                }
                synchronized(this) {
                    entries?.add(Entry(t.id, name, t.durationMs, t.sizeBytes, System.currentTimeMillis()))
                    saveIndex(ctx)
                }
                locked++
            } catch (e: Exception) {
                Log.e(TAG, "lock ${t.id}", e)
                tmp.delete(); out.delete(); captionFile(ctx, name).delete(); metaFile(ctx, name).delete()
                continue
            }
            // Only now remove the plain original (and its plain caption and metadata).
            if (TapeStore.delete(ctx, listOf(t)) > 0) left++
        }
        TapeStore.bump()
        return LockResult(locked, left)
    }

    /** Decrypts vault tapes back onto the public shelf. Returns how many came out. */
    fun takeOut(ctx: Context, tapes: Collection<Tape>): Int {
        val k = key ?: return 0
        var n = 0
        for (t in tapes) {
            val name = t.vault ?: continue
            if (Player.playingId.value == t.id) Player.stop()
            try {
                val ok = SealedFile(tapeFile(ctx, name), k).use { sf -> TapeStore.putOnShelf(ctx, t.id, sf.inputStream(), t.title) }
                if (!ok) continue
                TapeMeta.parse(readMeta(ctx, name, k))?.let { MetaStore.writePlain(ctx, t.id, it) }
                val cc = captionFile(ctx, name)
                if (cc.exists()) SealedFile(cc, k).use { sf ->
                    Captions.file(ctx, t.id).outputStream().use { o -> sf.inputStream().copyTo(o) }
                }
                remove(ctx, name)
                n++
            } catch (e: Exception) {
                Log.e(TAG, "take out ${t.id}", e)
            }
        }
        TapeStore.bump()
        return n
    }

    fun erase(ctx: Context, tapes: Collection<Tape>) {
        tapes.forEach { t ->
            val name = t.vault ?: return@forEach
            if (Player.playingId.value == t.id) Player.stop()
            remove(ctx, name)
        }
        TapeStore.bump()
    }

    private fun remove(ctx: Context, name: String) {
        tapeFile(ctx, name).delete()
        captionFile(ctx, name).delete()
        metaFile(ctx, name).delete()
        titles.remove(name)
        synchronized(this) {
            entries?.removeAll { it.file == name }
            saveIndex(ctx)
        }
    }

    /** Plain copies for sending, in [sendDir]. */
    fun exportForSending(ctx: Context, tapes: List<Tape>): List<File> {
        val k = key ?: return emptyList()
        val d = sendDir(ctx).apply { mkdirs() }
        return tapes.mapNotNull { t ->
            val name = t.vault ?: return@mapNotNull null
            runCatching {
                val f = File(d, t.id)
                SealedFile(tapeFile(ctx, name), k).use { sf -> f.outputStream().use { sf.inputStream().copyTo(it) } }
                TapeMeta.parse(readMeta(ctx, name, k))?.let { MetaStore.tagCopy(f, t.id, it) }
                f
            }.onFailure { Log.e(TAG, "export ${t.id}", it) }.getOrNull()
        }
    }

    /** Player source for a vault tape, or null when locked. */
    fun source(ctx: Context, t: Tape, k: SecretKey? = key): MediaDataSource? {
        if (k == null) return null
        val name = t.vault ?: return null
        return VaultSource(SealedFile(tapeFile(ctx, name), k))
    }

    fun readCaption(ctx: Context, name: String, k: SecretKey? = key): String? {
        val f = captionFile(ctx, name)
        if (k == null || !f.exists()) return null
        return runCatching { SealedFile(f, k).use { String(it.inputStream().readBytes()) } }
            .onFailure { Log.e(TAG, "caption $name", it) }.getOrNull()
    }

    /** @param k a key captured when the job started, so captioning can finish after a lock. */
    fun writeCaption(ctx: Context, name: String, text: String, k: SecretKey) {
        if (!tapeFile(ctx, name).exists()) return   // erased meanwhile
        val f = captionFile(ctx, name)
        val tmp = File(f.parentFile, f.name + ".part")
        SealedOut(FileOutputStream(tmp), k).use { it.write(text.toByteArray()) }
        f.replaceWith(tmp)
        if (!tapeFile(ctx, name).exists()) f.delete()
    }

    fun deleteCaption(ctx: Context, name: String) { captionFile(ctx, name).delete() }

    fun readMeta(ctx: Context, name: String, k: SecretKey? = key): String? {
        val f = metaFile(ctx, name)
        if (k == null || !f.exists()) return null
        return runCatching { SealedFile(f, k).use { String(it.inputStream().readBytes()) } }
            .onFailure { Log.e(TAG, "meta $name", it) }.getOrNull()
    }

    fun writeMeta(ctx: Context, name: String, json: String) {
        val k = key ?: throw IllegalStateException("vault is locked")
        if (!tapeFile(ctx, name).exists()) return
        val f = metaFile(ctx, name)
        val tmp = File(f.parentFile, f.name + ".part")
        SealedOut(FileOutputStream(tmp), k).use { it.write(json.toByteArray()) }
        f.replaceWith(tmp)
        titles[name] = TapeMeta.parse(json)?.title.orEmpty()
    }

    // ---- Sealed file format ---------------------------------------------------------------
    //
    // header: "D2PV" | version (1) | 3 reserved | file id (16)                    = 24 bytes
    // then records: IV (12) | AES-GCM(chunk ≤ 64 KiB) | tag (16)
    // AAD per record: file id | chunk index (8) | last-chunk flag (1). Reordering, swapping
    // between files and truncation all fail authentication.

    private const val CHUNK = 64 * 1024
    private const val IV = 12
    private const val TAGLEN = 16
    private const val REC = CHUNK + IV + TAGLEN
    private const val HDR = 24
    private val MAGIC = byteArrayOf('D'.code.toByte(), '2'.code.toByte(), 'P'.code.toByte(), 'V'.code.toByte())

    private fun aad(fid: ByteArray, idx: Long, last: Boolean): ByteArray {
        val a = ByteArray(25)
        fid.copyInto(a)
        for (i in 0 until 8) a[16 + i] = (idx ushr (56 - 8 * i)).toByte()
        a[24] = if (last) 1 else 0
        return a
    }

    internal class SealedOut(private val out: OutputStream, private val k: SecretKey) : OutputStream() {
        private val fid = ByteArray(16).also(rng::nextBytes)
        private val buf = ByteArray(CHUNK)
        private var n = 0
        private var idx = 0L
        private val c = Cipher.getInstance("AES/GCM/NoPadding")
        private var closed = false

        init {
            out.write(MAGIC); out.write(byteArrayOf(1, 0, 0, 0)); out.write(fid)
        }

        override fun write(b: Int) {
            buf[n++] = b.toByte()
            if (n == CHUNK) seal(false)
        }

        override fun write(b: ByteArray, off: Int, len: Int) {
            var o = off; var left = len
            while (left > 0) {
                val k = minOf(left, CHUNK - n)
                System.arraycopy(b, o, buf, n, k)
                n += k; o += k; left -= k
                if (n == CHUNK) seal(false)
            }
        }

        private fun seal(last: Boolean) {
            val iv = ByteArray(IV).also(rng::nextBytes)
            c.init(Cipher.ENCRYPT_MODE, k, GCMParameterSpec(128, iv))
            c.updateAAD(aad(fid, idx, last))
            out.write(iv)
            out.write(c.doFinal(buf, 0, n))
            idx++; n = 0
        }

        override fun close() {
            if (closed) return
            closed = true
            seal(true)   // always a final (possibly empty) record, so truncation is detectable
            (out as? FileOutputStream)?.fd?.sync()
            out.close()
        }
    }

    /** Random-access reader for a sealed file. */
    class SealedFile(f: File, private val k: SecretKey) : Closeable {
        private val raf = RandomAccessFile(f, "r")
        private val fid = ByteArray(16)
        private val chunks: Long
        val size: Long
        private val c = Cipher.getInstance("AES/GCM/NoPadding")
        private val rec = ByteArray(REC)
        private val plain = ByteArray(CHUNK)
        private var plainLen = 0
        private var cached = -1L

        init {
            val hdr = ByteArray(HDR)
            raf.readFully(hdr)
            require(hdr.copyOfRange(0, 4).contentEquals(MAGIC) && hdr[4] == 1.toByte()) { "not a vault file" }
            hdr.copyInto(fid, 0, 8, 24)
            val body = raf.length() - HDR
            chunks = body / REC + if (body % REC > 0) 1 else 0
            size = body - chunks * (IV + TAGLEN)
            require(chunks > 0 && size >= 0) { "truncated vault file" }
        }

        private fun load(ci: Long) {
            if (ci == cached) return
            val start = HDR + ci * REC
            val len = minOf(REC.toLong(), raf.length() - start).toInt()
            raf.seek(start)
            raf.readFully(rec, 0, len)
            c.init(Cipher.DECRYPT_MODE, k, GCMParameterSpec(128, rec, 0, IV))
            c.updateAAD(aad(fid, ci, ci == chunks - 1))
            plainLen = c.doFinal(rec, IV, len - IV, plain, 0)
            cached = ci
        }

        @Synchronized
        fun readAt(pos: Long, dst: ByteArray, off: Int, len: Int): Int {
            if (pos >= size) return -1
            var p = pos; var o = off
            var left = minOf(len.toLong(), size - pos).toInt()
            var total = 0
            while (left > 0) {
                load(p / CHUNK)
                val inOff = (p % CHUNK).toInt()
                val k = minOf(left, plainLen - inOff)
                if (k <= 0) break
                System.arraycopy(plain, inOff, dst, o, k)
                p += k; o += k; left -= k; total += k
            }
            return total
        }

        fun inputStream(): InputStream = object : InputStream() {
            private var pos = 0L
            override fun read(): Int {
                val b = ByteArray(1)
                return if (read(b, 0, 1) <= 0) -1 else b[0].toInt() and 0xFF
            }
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                if (len == 0) return 0
                val n = readAt(pos, b, off, len)
                if (n > 0) pos += n
                return n
            }
        }

        override fun close() = raf.close()
    }

    private class VaultSource(private val f: SealedFile) : MediaDataSource() {
        override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int =
            if (size == 0) 0 else f.readAt(position, buffer, offset, size)
        override fun getSize(): Long = f.size
        override fun close() = f.close()
    }
}
