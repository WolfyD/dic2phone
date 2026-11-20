import AVFoundation

/// Encodes one tape to AAC in an .m4a file.
///
/// The file is written in movie fragments every few seconds, so if the app is killed
/// mid-tape the file stays readable up to its last fragment and `TapeRescue` saves it on
/// the next launch.
final class AssetTapeWriter: TapeSink {
    private static let fragmentSeconds = 5.0
    private static let readyPollLimit = 100

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let format: CMAudioFormatDescription

    init(url: URL) throws {
        format = try PCMBuffers.formatDescription()
        writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        writer.movieFragmentInterval = CMTime(seconds: Self.fragmentSeconds, preferredTimescale: 600)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: TapeFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: TapeFormat.bitRate,
        ]
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings, sourceFormatHint: format)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw RecordingError.writerFailed }
        writer.add(input)
        guard writer.startWriting() else { throw RecordingError.writerFailed }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ samples: [Int16], at sampleTime: Int64) async throws {
        let buffer = try PCMBuffers.sampleBuffer(samples, startingAt: sampleTime, format: format)
        var polls = 0
        while !input.isReadyForMoreMediaData {
            guard writer.status == .writing, polls < Self.readyPollLimit else { throw RecordingError.writerFailed }
            polls += 1
            try await Task.sleep(for: .milliseconds(5))
        }
        guard input.append(buffer) else { throw RecordingError.writerFailed }
    }

    func finish() async -> Bool {
        guard writer.status == .writing else { return false }
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed
    }
}
