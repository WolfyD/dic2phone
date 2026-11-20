import AVFoundation

/// Plays a vault tape straight from its sealed file. AVPlayer asks for byte ranges, and each
/// is decrypted in memory as it's handed over, so the tape is never on disk unencrypted.
final class SealedAssetLoader: NSObject, AVAssetResourceLoaderDelegate, Sendable {
    /// A scheme AVPlayer can't load by itself, so it has to ask this loader for every byte.
    private static let scheme = "dic2phone-vault"
    /// Answers go back in pieces this size, so a cancelled request stops soon.
    private static let pieceSize = 256 * 1024

    private let file: SealedFile
    private let queue = DispatchQueue(label: "com.dic2phone.sealed-asset", qos: .userInitiated, attributes: .concurrent)

    init(file: SealedFile) {
        self.file = file
    }

    /// An item that reads through this loader. The asset holds its loader weakly, so whoever
    /// plays the item must keep the loader too.
    func makeItem() -> AVPlayerItem? {
        makeAsset().map { AVPlayerItem(asset: $0) }
    }

    /// An asset that reads through this loader, which whoever uses it must keep.
    func makeAsset() -> AVURLAsset? {
        guard let url = URL(string: "\(Self.scheme)://tape") else { return nil }
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(self, queue: queue)
        return asset
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        do {
            let reader = try file.reader()
            if let information = loadingRequest.contentInformationRequest {
                information.contentType = AVFileType.m4a.rawValue
                information.contentLength = reader.size
                information.isByteRangeAccessSupported = true
            }
            if let dataRequest = loadingRequest.dataRequest {
                try respond(to: dataRequest, of: loadingRequest, from: reader)
            }
            loadingRequest.finishLoading()
        } catch {
            loadingRequest.finishLoading(with: error)
        }
        return true
    }

    private func respond(
        to dataRequest: AVAssetResourceLoadingDataRequest,
        of loadingRequest: AVAssetResourceLoadingRequest,
        from reader: SealedFileReader
    ) throws {
        let requestedEnd = dataRequest.requestedOffset + Int64(dataRequest.requestedLength)
        let end = dataRequest.requestsAllDataToEndOfResource ? reader.size : min(requestedEnd, reader.size)
        var offset = dataRequest.currentOffset
        while offset < end, !loadingRequest.isCancelled {
            let count = Int(min(Int64(Self.pieceSize), end - offset))
            dataRequest.respond(with: try reader.read(from: offset, count: count))
            offset += Int64(count)
        }
    }
}
