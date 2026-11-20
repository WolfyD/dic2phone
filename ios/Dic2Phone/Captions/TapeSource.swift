import AVFoundation

/// Where a tape to transcribe is read from: its plain file, or its sealed one in the vault,
/// decrypted only in memory.
enum TapeSource: Sendable {
    case plain(URL)
    case sealed(SealedFile)

    func samples() async throws -> TapeSamples {
        switch self {
        case .plain(let url):
            return try await TapeSamples(asset: AVURLAsset(url: url))
        case .sealed(let file):
            let loader = SealedAssetLoader(file: file)
            guard let asset = loader.makeAsset() else { throw CaptionError.tapeUnreadable }
            return try await TapeSamples(asset: asset, loader: loader)
        }
    }
}
