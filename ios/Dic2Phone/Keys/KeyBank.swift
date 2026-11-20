import SwiftUI

/// A row of piano keys like a portable recorder's transport, each key's label printed on the
/// faceplate above it.
struct KeyBank: View {
    let keys: [BankKey]
    let keyHeight: CGFloat

    @Environment(\.palette) private var palette
    @Environment(\.keyClick) private var keyClick

    var body: some View {
        VStack(spacing: 4) {
            WeightedRow(spacing: 3) {
                ForEach(keys) { key in
                    printedLabel(of: key).layoutWeight(key.weight)
                }
            }
            .accessibilityHidden(true)
            WeightedRow(spacing: 3) {
                ForEach(keys) { key in
                    pianoKey(for: key).layoutWeight(key.weight)
                }
            }
            .padding(3)
            .background(Color(hex: 0x050505), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            LinearGradient(colors: [palette.panel.mix(with: .white, by: 0.12), palette.panel], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.5), lineWidth: 1))
    }

    /// Translated labels can outgrow their key, so they shrink rather than wrap.
    private func printedLabel(of key: BankKey) -> some View {
        Text(verbatim: key.label)
            .font(DeckFont.monoBold.fixed(10))
            .tracking(1)
            .foregroundStyle(key.labelColor ?? palette.dim)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func pianoKey(for key: BankKey) -> some View {
        let face1 = key.face1 ?? palette.key1
        let face2 = key.face2 ?? palette.key2
        switch key.action {
        case .tap(let action):
            Button {
                keyClick()
                action()
            } label: {
                face(of: key)
            }
            .buttonStyle(PianoKeyStyle(height: keyHeight, face1: face1, face2: face2, latched: key.latched))
            .accessibilityLabel(Text(verbatim: key.label))
        case .hold(let press, let release):
            HoldKey(height: keyHeight, face1: face1, face2: face2, latched: key.latched, onPress: press, onRelease: release) {
                face(of: key)
            }
            .accessibilityLabel(Text(verbatim: key.label))
        }
    }

    @ViewBuilder
    private func face(of key: BankKey) -> some View {
        let color = key.glyphColor ?? palette.keyText
        switch key.face {
        case .glyph(let glyph):
            Text(verbatim: glyph)
                .font(DeckFont.monoBold.fixed(18))
                .foregroundStyle(color)
        case .icon(let icon):
            Canvas { context, size in
                icon.draw(in: context, size: size, color: color)
            }
            .frame(width: 26, height: 22)
        }
    }
}
