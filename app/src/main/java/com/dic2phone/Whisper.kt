package com.dic2phone

import android.util.Log
import java.io.Closeable

/** Thin bridge to whisper.cpp (app/src/main/cpp). */
object Whisper {
    /** The library is built for ARMv8.2 + half-precision SIMD; older CPUs would crash in it. */
    private val cpuOk: Boolean = runCatching {
        java.io.File("/proc/cpuinfo").readLines().firstOrNull { it.startsWith("Features") }
            ?.split(' ', '\t', ':')?.contains("asimdhp") ?: true
    }.getOrDefault(true)

    val available: Boolean = cpuOk && runCatching { System.loadLibrary("d2pwhisper"); true }
        .onFailure { Log.e("Whisper", "native library missing", it) }
        .getOrDefault(false)

    class Segment(val startMs: Long, val endMs: Long, val text: String)

    /**
     * A loaded model. [transcribe] and [close] belong to one thread; [progress] and [cancel] may
     * be called from any thread, so they share a lock with [close] and never see a freed handle.
     */
    class Model private constructor(@Volatile private var h: Long) : Closeable {
        private val lock = Any()

        /** 0..100 for the current [transcribe] call. */
        val progress: Int get() = synchronized(lock) { if (h != 0L) nProgress(h) else 0 }

        /** Ask a running [transcribe] to stop soon. */
        fun cancel() { synchronized(lock) { if (h != 0L) nAbort(h, true) } }

        /** @return segments with times relative to the start of [pcm], or null if cancelled/failed. */
        fun transcribe(pcm: FloatArray, lang: String, threads: Int): List<Segment>? {
            check(h != 0L) { "model closed" }
            nAbort(h, false)
            val r = nFull(h, pcm, lang, threads)
            if (r != 0) { Log.w("Whisper", "whisper_full returned $r"); return null }
            return (0 until nSegments(h)).map { i ->
                Segment(nT0(h, i), nT1(h, i), String(nText(h, i), Charsets.UTF_8))
            }
        }

        override fun close() { synchronized(lock) { if (h != 0L) { nFree(h); h = 0L } } }

        companion object {
            fun load(path: String): Model? =
                if (!available) null else nInit(path).takeIf { it != 0L }?.let { Model(it) }
        }
    }

    @JvmStatic private external fun nInit(path: String): Long
    @JvmStatic private external fun nFree(h: Long)
    @JvmStatic private external fun nAbort(h: Long, on: Boolean)
    @JvmStatic private external fun nProgress(h: Long): Int
    @JvmStatic private external fun nFull(h: Long, pcm: FloatArray, lang: String, threads: Int): Int
    @JvmStatic private external fun nSegments(h: Long): Int
    @JvmStatic private external fun nT0(h: Long, i: Int): Long
    @JvmStatic private external fun nT1(h: Long, i: Int): Long
    @JvmStatic private external fun nText(h: Long, i: Int): ByteArray
}
