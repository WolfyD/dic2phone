import Foundation
import Synchronization
import WhisperCpp

/// A loaded whisper.cpp speech model. Besides `PCMBuffers`, the only type that handles raw
/// pointers (CWE-787/125/416): every pointer handed to whisper lives only for the call it is
/// passed to.
///
/// Unchecked Sendable: `transcribe` is only ever run by one task at a time (the caption queue),
/// while `cancel` and `progress` may come from anywhere and touch nothing but atomics.
final class WhisperModel: @unchecked Sendable {
    private static let threads = min(max(ProcessInfo.processInfo.activeProcessorCount, 1), 4)
    /// Lines short enough to read as a caption.
    private static let maxLineLength: Int32 = 64

    private let context: OpaquePointer
    private let cancelled = Atomic<Bool>(false)
    private let percentDone = Atomic<Int>(0)

    init(contentsOf url: URL) throws {
        // whisper.cpp logs model details and file paths to the console (CWE-532).
        whisper_log_set({ _, _, _ in }, nil)
        var params = whisper_context_default_params()
        params.use_gpu = false
        let context = url.withUnsafeFileSystemRepresentation { path -> OpaquePointer? in
            guard let path else { return nil }
            return whisper_init_from_file_with_params(path, params)
        }
        guard let context else { throw CaptionError.modelUnreadable }
        self.context = context
    }

    deinit {
        whisper_free(context)
    }

    /// How far the running `transcribe` call has got, 0…100.
    var progress: Int {
        percentDone.load(ordering: .relaxed)
    }

    /// Stops the running `transcribe` call soon; it then throws `CancellationError`.
    func cancel() {
        cancelled.store(true, ordering: .relaxed)
    }

    /// - Parameters:
    ///   - samples: 16 kHz mono audio.
    ///   - language: a whisper language code, or "auto".
    /// - Returns: what was said, timed from the start of `samples`.
    func transcribe(_ samples: [Float], language: String) throws -> [Cue] {
        guard let count = Int32(exactly: samples.count) else { throw CaptionError.transcriptionFailed }
        cancelled.store(false, ordering: .relaxed)
        percentDone.store(0, ordering: .relaxed)
        let status = language.withCString { language in
            samples.withUnsafeBufferPointer { samples in
                whisper_full(context, parameters(language: language), samples.baseAddress, count)
            }
        }
        if cancelled.load(ordering: .relaxed) { throw CancellationError() }
        guard status == 0 else { throw CaptionError.transcriptionFailed }
        return segments()
    }

    private func parameters(language: UnsafePointer<CChar>) -> whisper_full_params {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(Self.threads)
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.print_timestamps = false
        params.translate = false
        params.no_context = true
        // No "[Music]" or "(applause)" captions.
        params.suppress_nst = true
        // Token timestamps are what max_len splits on.
        params.token_timestamps = true
        params.max_len = Self.maxLineLength
        params.split_on_word = true
        params.language = language
        params.detect_language = false

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        params.progress_callback = { _, _, progress, userData in
            WhisperModel.from(userData)?.percentDone.store(Int(progress), ordering: .relaxed)
        }
        params.progress_callback_user_data = selfPointer
        params.abort_callback = { userData in
            WhisperModel.from(userData)?.cancelled.load(ordering: .relaxed) ?? true
        }
        params.abort_callback_user_data = selfPointer
        params.encoder_begin_callback = { _, _, userData in
            !(WhisperModel.from(userData)?.cancelled.load(ordering: .relaxed) ?? true)
        }
        params.encoder_begin_callback_user_data = selfPointer
        return params
    }

    private func segments() -> [Cue] {
        (0..<whisper_full_n_segments(context)).compactMap { index in
            guard let text = whisper_full_get_segment_text(context, index) else { return nil }
            // Segment times are in hundredths of a second. A segment may end mid-character;
            // String(cString:) mends broken UTF-8 rather than failing.
            return Cue(
                startMs: whisper_full_get_segment_t0(context, index) * 10,
                endMs: whisper_full_get_segment_t1(context, index) * 10,
                text: String(cString: text)
            )
        }
    }

    private static func from(_ pointer: UnsafeMutableRawPointer?) -> WhisperModel? {
        pointer.map { Unmanaged<WhisperModel>.fromOpaque($0).takeUnretainedValue() }
    }
}
