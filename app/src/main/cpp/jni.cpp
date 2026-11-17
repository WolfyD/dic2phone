// JNI bridge to whisper.cpp for com.dic2phone.Whisper.
// No callbacks into Java: progress and cancel go through atomics that Kotlin polls / sets,
// so whisper's worker threads never touch the JVM.

#include <jni.h>
#include <android/log.h>
#include <atomic>
#include <cstring>
#include "whisper.h"

#define TAG "whisper"

namespace {

struct Handle {
    whisper_context *ctx = nullptr;
    std::atomic<bool> abort{false};
    std::atomic<int> progress{0};
};

void log_cb(ggml_log_level level, const char *text, void *) {
    int prio = level == GGML_LOG_LEVEL_ERROR ? ANDROID_LOG_ERROR
             : level == GGML_LOG_LEVEL_WARN  ? ANDROID_LOG_WARN
             : ANDROID_LOG_DEBUG;
    __android_log_write(prio, TAG, text);
}

Handle *H(jlong h) { return reinterpret_cast<Handle *>(h); }

} // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_dic2phone_Whisper_nInit(JNIEnv *env, jobject, jstring path) {
    whisper_log_set(log_cb, nullptr);
    const char *p = env->GetStringUTFChars(path, nullptr);
    if (!p) return 0;
    whisper_context_params cp = whisper_context_default_params();
    cp.use_gpu = false;
    whisper_context *ctx = whisper_init_from_file_with_params(p, cp);
    env->ReleaseStringUTFChars(path, p);
    if (!ctx) return 0;
    auto *h = new Handle();
    h->ctx = ctx;
    return reinterpret_cast<jlong>(h);
}

JNIEXPORT void JNICALL
Java_com_dic2phone_Whisper_nFree(JNIEnv *, jobject, jlong h) {
    if (!h) return;
    whisper_free(H(h)->ctx);
    delete H(h);
}

JNIEXPORT void JNICALL
Java_com_dic2phone_Whisper_nAbort(JNIEnv *, jobject, jlong h, jboolean on) {
    if (h) H(h)->abort.store(on);
}

JNIEXPORT jint JNICALL
Java_com_dic2phone_Whisper_nProgress(JNIEnv *, jobject, jlong h) {
    return h ? H(h)->progress.load() : 0;
}

/** Transcribe 16 kHz mono float PCM. Returns 0 on success. Results via nSegments/nT0/nT1/nText. */
JNIEXPORT jint JNICALL
Java_com_dic2phone_Whisper_nFull(JNIEnv *env, jobject, jlong hh, jfloatArray pcm, jstring lang, jint threads) {
    Handle *h = H(hh);
    if (!h) return -1;
    h->progress.store(0);

    whisper_full_params wp = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    wp.n_threads = threads;
    wp.print_progress = false;
    wp.print_realtime = false;
    wp.print_special = false;
    wp.print_timestamps = false;
    wp.translate = false;
    wp.no_context = true;
    wp.suppress_nst = true;        // no "[Music]" / "(applause)" style tokens
    wp.token_timestamps = true;    // needed for max_len splitting
    wp.max_len = 64;               // caption-sized lines
    wp.split_on_word = true;

    const char *l = env->GetStringUTFChars(lang, nullptr);
    if (!l) return -1;
    wp.language = l;
    wp.detect_language = false;

    wp.progress_callback = [](whisper_context *, whisper_state *, int p, void *u) {
        static_cast<Handle *>(u)->progress.store(p);
    };
    wp.progress_callback_user_data = h;
    wp.abort_callback = [](void *u) { return static_cast<Handle *>(u)->abort.load(); };
    wp.abort_callback_user_data = h;
    wp.encoder_begin_callback = [](whisper_context *, whisper_state *, void *u) {
        return !static_cast<Handle *>(u)->abort.load();
    };
    wp.encoder_begin_callback_user_data = h;

    jsize n = env->GetArrayLength(pcm);
    jfloat *data = env->GetFloatArrayElements(pcm, nullptr);
    if (!data) { env->ReleaseStringUTFChars(lang, l); return -1; }
    int r = whisper_full(h->ctx, wp, data, n);
    env->ReleaseFloatArrayElements(pcm, data, JNI_ABORT);
    env->ReleaseStringUTFChars(lang, l);
    if (h->abort.load()) return -2;
    return r;
}

JNIEXPORT jint JNICALL
Java_com_dic2phone_Whisper_nSegments(JNIEnv *, jobject, jlong h) {
    return whisper_full_n_segments(H(h)->ctx);
}

/** Segment start, in ms. */
JNIEXPORT jlong JNICALL
Java_com_dic2phone_Whisper_nT0(JNIEnv *, jobject, jlong h, jint i) {
    return whisper_full_get_segment_t0(H(h)->ctx, i) * 10;
}

JNIEXPORT jlong JNICALL
Java_com_dic2phone_Whisper_nT1(JNIEnv *, jobject, jlong h, jint i) {
    return whisper_full_get_segment_t1(H(h)->ctx, i) * 10;
}

/** Raw UTF-8 bytes (a segment may end mid-character, so Kotlin decodes leniently). */
JNIEXPORT jbyteArray JNICALL
Java_com_dic2phone_Whisper_nText(JNIEnv *env, jobject, jlong h, jint i) {
    const char *t = whisper_full_get_segment_text(H(h)->ctx, i);
    jsize len = t ? (jsize) strlen(t) : 0;
    jbyteArray out = env->NewByteArray(len);
    if (out && len) env->SetByteArrayRegion(out, 0, len, reinterpret_cast<const jbyte *>(t));
    return out;
}

} // extern "C"
