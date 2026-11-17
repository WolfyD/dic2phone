package com.dic2phone

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import javax.crypto.spec.SecretKeySpec
import kotlin.random.Random

/** The vault's chunked AES-GCM file format. */
class SealedFileTest {
    @get:Rule val tmp = TemporaryFolder()

    private val key = SecretKeySpec(Random(1).nextBytes(32), "AES")
    private val chunk = 64 * 1024

    private fun seal(data: ByteArray): File = tmp.newFile().also { f ->
        Vault.SealedOut(FileOutputStream(f), key).use { it.write(data) }
    }

    private fun open(f: File) = Vault.SealedFile(f, key).use { it.inputStream().readBytes() }

    @Test fun roundTripsAllSizes() {
        for (n in listOf(0, 1, 1000, chunk - 1, chunk, chunk + 1, 3 * chunk + 17)) {
            val data = Random(n).nextBytes(n)
            assertArrayEquals("size $n", data, open(seal(data)))
        }
    }

    @Test fun randomAccessReads() {
        val data = Random(2).nextBytes(2 * chunk + 100)
        Vault.SealedFile(seal(data), key).use { sf ->
            assertEquals(data.size.toLong(), sf.size)
            val buf = ByteArray(200)
            val pos = chunk - 50L   // straddles a chunk boundary
            assertEquals(200, sf.readAt(pos, buf, 0, 200))
            assertArrayEquals(data.copyOfRange(pos.toInt(), pos.toInt() + 200), buf)
            assertEquals(-1, sf.readAt(data.size.toLong(), buf, 0, 1))
        }
    }

    @Test fun tamperedByteFailsAuthentication() {
        val f = seal(Random(3).nextBytes(5000))
        RandomAccessFile(f, "rw").use { it.seek(100); val b = it.read(); it.seek(100); it.write(b xor 1) }
        assertFails { open(f) }
    }

    @Test fun truncationIsDetected() {
        val data = Random(4).nextBytes(2 * chunk)
        val f = seal(data)
        // Drop the final record: what's left still parses, but its last chunk wasn't sealed as last.
        RandomAccessFile(f, "rw").use { it.setLength(it.length() - 28) }
        assertFails { open(f) }
    }

    @Test fun wrongKeyFails() {
        val f = seal(ByteArray(10))
        val other = SecretKeySpec(Random(9).nextBytes(32), "AES")
        assertFails { Vault.SealedFile(f, other).use { it.inputStream().readBytes() } }
    }

    @Test fun notAVaultFileIsRejected() {
        val f = tmp.newFile().apply { writeBytes(ByteArray(100)) }
        assertFails { Vault.SealedFile(f, key) }
    }

    private fun assertFails(block: () -> Unit) {
        try { block() } catch (_: Exception) { return }
        fail("expected a failure")
    }
}
