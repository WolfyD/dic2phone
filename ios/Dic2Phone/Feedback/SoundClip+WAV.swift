import Foundation

extension SoundClip {
    /// The clip as a 16-bit mono WAV file in memory, which AVAudioPlayer can play directly.
    var wavData: Data {
        let dataBytes = UInt32(samples.count * 2)
        var wav = Data()
        wav.reserveCapacity(44 + samples.count * 2)
        wav.append(contentsOf: Array("RIFF".utf8))
        wav.appendLittleEndian(36 + dataBytes)
        wav.append(contentsOf: Array("WAVEfmt ".utf8))
        wav.appendLittleEndian(UInt32(16))
        wav.appendLittleEndian(UInt16(1))
        wav.appendLittleEndian(UInt16(1))
        wav.appendLittleEndian(UInt32(sampleRate))
        wav.appendLittleEndian(UInt32(sampleRate * 2))
        wav.appendLittleEndian(UInt16(2))
        wav.appendLittleEndian(UInt16(16))
        wav.append(contentsOf: Array("data".utf8))
        wav.appendLittleEndian(dataBytes)
        for sample in samples {
            wav.appendLittleEndian(UInt16(bitPattern: sample))
        }
        return wav
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: some FixedWidthInteger) {
        for shift in stride(from: 0, to: value.bitWidth, by: 8) {
            append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }
}
