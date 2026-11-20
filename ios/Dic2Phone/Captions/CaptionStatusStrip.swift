import SwiftUI

/// "TRANSCRIBING 1/3 · LISTENING 42%" with a key to stop, while transcripts are being made; why
/// the last one failed, if it did.
struct CaptionStatusStrip: View {
    @Environment(CaptionQueue.self) private var captions
    @Environment(\.palette) private var palette

    var body: some View {
        if let status = captions.status {
            strip(status)
        } else if let error = captions.lastError {
            Text(verbatim: String(localized: "TRANSCRIBING FAILED: \(error)"))
                .font(DeckFont.mono.fixed(11))
                .foregroundStyle(palette.danger)
                .lineLimit(2)
        }
    }

    private func strip(_ status: CaptionStatus) -> some View {
        HStack(spacing: 8) {
            Led(on: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: String(localized: "TRANSCRIBING \(status.index)/\(status.total) · \(status.step.line) \(status.percent)%"))
                    .font(DeckFont.monoBold.fixed(12))
                    .foregroundStyle(palette.led)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                TapeProgress(progress: CGFloat(status.percent) / 100, track: .white.opacity(0.15))
                    .frame(height: 3)
            }
            DeckKey(label: String(localized: "CANCEL"), height: 34, action: captions.cancelAll)
                .frame(width: 84)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
    }
}
