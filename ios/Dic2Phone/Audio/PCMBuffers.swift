import AVFoundation
import CoreMedia

/// The one place (besides the whisper.cpp bridge) that touches raw memory: moving samples
/// between Swift arrays and Core Audio buffers. Every copy is bounded by the sizes of both
/// sides (CWE-787/125).
enum PCMBuffers {
    static let tapeFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Double(TapeFormat.sampleRate),
        channels: 1,
        interleaved: true
    )

    static func samples(from buffer: AVAudioPCMBuffer) -> [Int16] {
        guard buffer.format.commonFormat == .pcmFormatInt16,
              buffer.format.channelCount == 1,
              let channels = buffer.int16ChannelData else { return [] }
        let count = Int(min(buffer.frameLength, buffer.frameCapacity))
        return Array(UnsafeBufferPointer(start: channels[0], count: count))
    }

    /// Converts one microphone buffer to the tape format. The converter keeps its resampling
    /// state between calls, so it must be the same converter for the whole recording.
    static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> [Int16] {
        let ratio = converter.outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return [] }
        var handedOver = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if handedOver {
                inputStatus.pointee = .noDataNow
                return nil
            }
            handedOver = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error else { return [] }
        return samples(from: output)
    }

    /// The samples in a buffer an asset reader decoded to 32-bit float mono; none if the buffer
    /// holds anything else.
    static func floats(from sampleBuffer: CMSampleBuffer) -> [Float] {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              description.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              description.mBitsPerChannel == 32,
              description.mChannelsPerFrame == 1,
              let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return [] }
        let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
        var samples = [Float](repeating: 0, count: count)
        let status = samples.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress, bytes.count == count * MemoryLayout<Float>.size else {
                return kCMBlockBufferBadLengthParameterErr
            }
            return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: base)
        }
        return status == kCMBlockBufferNoErr ? samples : []
    }

    static func formatDescription() throws -> CMAudioFormatDescription {
        var description = AudioStreamBasicDescription(
            mSampleRate: Float64(TapeFormat.sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var format: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &description,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        )
        guard status == noErr, let format else { throw RecordingError.writerFailed }
        return format
    }

    static func sampleBuffer(
        _ samples: [Int16],
        startingAt sampleTime: Int64,
        format: CMAudioFormatDescription
    ) throws -> CMSampleBuffer {
        guard !samples.isEmpty else { throw RecordingError.writerFailed }
        let byteCount = samples.count * MemoryLayout<Int16>.size
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &block
        )
        guard status == kCMBlockBufferNoErr, let block else { throw RecordingError.writerFailed }
        status = samples.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress, bytes.count == byteCount,
                  CMBlockBufferGetDataLength(block) == byteCount else { return kCMBlockBufferBadLengthParameterErr }
            return CMBlockBufferReplaceDataBytes(with: base, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
        }
        guard status == kCMBlockBufferNoErr else { throw RecordingError.writerFailed }
        var sampleBuffer: CMSampleBuffer?
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: samples.count,
            presentationTimeStamp: CMTime(value: sampleTime, timescale: CMTimeScale(TapeFormat.sampleRate)),
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else { throw RecordingError.writerFailed }
        return sampleBuffer
    }
}
