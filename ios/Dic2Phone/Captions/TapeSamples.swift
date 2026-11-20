import AVFoundation

/// Decodes a tape to the 16 kHz mono float samples whisper.cpp listens to, a little at a time,
/// so an hour-long tape never has to be in memory whole.
final class TapeSamples {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    /// A vault tape's asset only holds its loader weakly.
    private let loader: SealedAssetLoader?

    init(asset: AVURLAsset, loader: SealedAssetLoader? = nil) async throws {
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { throw CaptionError.tapeUnreadable }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: SpeechPieces.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        guard reader.canAdd(output) else { throw CaptionError.tapeUnreadable }
        reader.add(output)
        guard reader.startReading() else { throw CaptionError.tapeUnreadable }
        self.reader = reader
        self.output = output
        self.loader = loader
    }

    /// - Returns: the next samples, or nil at the end of the tape.
    func next() throws -> [Float]? {
        guard let buffer = output.copyNextSampleBuffer() else {
            guard reader.status == .completed else { throw CaptionError.tapeUnreadable }
            return nil
        }
        return PCMBuffers.floats(from: buffer)
    }
}
