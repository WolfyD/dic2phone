import AVFoundation

/// Turns the microphone's buffers (any rate, any layout) into tape-format chunks of exactly
/// `TapeFormat.chunkSize` samples. Used only on the audio thread that feeds it.
final class MicChunker {
    private let converter: AVAudioConverter
    private var carry: [Int16] = []

    init(from inputFormat: AVAudioFormat) throws {
        guard let tapeFormat = PCMBuffers.tapeFormat,
              let converter = AVAudioConverter(from: inputFormat, to: tapeFormat) else {
            throw RecordingError.micUnavailable
        }
        self.converter = converter
    }

    func chunks(from buffer: AVAudioPCMBuffer) -> [[Int16]] {
        carry += PCMBuffers.convert(buffer, with: converter)
        var chunks: [[Int16]] = []
        while carry.count >= TapeFormat.chunkSize {
            chunks.append(Array(carry.prefix(TapeFormat.chunkSize)))
            carry.removeFirst(TapeFormat.chunkSize)
        }
        return chunks
    }
}
