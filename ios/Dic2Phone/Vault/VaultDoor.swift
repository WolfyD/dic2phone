import SwiftUI

/// The locked vault: a steel door with a dial, what the vault is, and the key that opens it,
/// or why it won't open.
struct VaultDoor: View {
    private static let dialSize: CGFloat = 96

    let isKeyLost: Bool
    let passcodeIsSet: Bool
    let unlock: () -> Void
    let reset: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        ViewThatFits(in: .vertical) {
            face
            ScrollView { face }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Steel.plate, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Steel.edge, lineWidth: 3))
    }

    private var face: some View {
        VStack(spacing: 14) {
            dial
            Text(verbatim: message)
                .font(DeckFont.mono.fixed(13))
                .foregroundStyle(Steel.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            key
        }
        .padding(18)
    }

    private var dial: some View {
        Text(verbatim: Glyph.locked)
            .font(.system(size: 36))
            .frame(width: Self.dialSize, height: Self.dialSize)
            .background(
                RadialGradient(
                    colors: [Color(hex: 0xC9CED3), Color(hex: 0x4A4F55)],
                    center: .center, startRadius: 0, endRadius: Self.dialSize / 2
                ),
                in: Circle()
            )
            .overlay(Circle().strokeBorder(Color(hex: 0x2C3035), lineWidth: 4))
            .accessibilityHidden(true)
    }

    private var message: String {
        if isKeyLost {
            String(localized: "The vault's key is gone. This happens when the phone's passcode is turned off: iOS deletes the key, and the tapes inside can't be decrypted any more.")
        } else if !passcodeIsSet {
            String(localized: "The vault needs a passcode on this phone. Set one in Settings › Face ID & Passcode, then come back.")
        } else {
            String(localized: "Tapes in here are encrypted on this phone and only play after Face ID or your passcode. Leaving the app locks the vault again.\n\nCareful: if you ever turn off the phone's passcode, iOS deletes the key and the tapes in the vault are lost for good. They're not in backups either.")
        }
    }

    @ViewBuilder
    private var key: some View {
        if isKeyLost {
            DeckKey(label: String(localized: "RESET VAULT"), labelColor: palette.danger, action: reset)
        } else if passcodeIsSet {
            DeckKey(label: String(localized: "UNLOCK"), action: unlock)
        }
    }
}
