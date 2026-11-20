import SwiftUI

/// The less-used keys, under a lid like the hidden controls on a real deck. Tapping the lid
/// flips it up to show the keys in their dark well; tapping it again closes it.
struct DeckCompartment<Keys: View>: View {
    /// The Android lid's spring: stiffness 500, damping ratio 0.8.
    private static var lidSpring: Animation {
        .spring(response: 0.28, dampingFraction: 0.8)
    }

    @ViewBuilder let keys: Keys

    @SceneStorage("deckCompartmentOpen") private var isOpen = false
    @Environment(\.detentClick) private var detentClick

    var body: some View {
        VStack(spacing: 3) {
            lid
            if isOpen {
                WeightedRow(spacing: 4) { keys }
                    .padding(4)
                    .background(Color(hex: 0x050505), in: RoundedRectangle(cornerRadius: 4))
                    .transition(.opacity)
            }
        }
    }

    private var lid: some View {
        Button {
            detentClick()
            withAnimation(Self.lidSpring) { isOpen.toggle() }
        } label: {
            CompartmentLid(flip: isOpen ? 1 : 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("More controls"))
        .accessibilityValue(isOpen ? Text("Open") : Text("Closed"))
    }
}
