import SwiftUI

/// The deck's varispeed: a short fader with a notch per speed. The knob sticks in its notch, lags
/// behind the finger, then clicks into the next one, and springs home when let go. A tap goes
/// straight to the nearest notch. Changes apply at once, also while the tape plays.
struct VarispeedFader: View {
    static let height: CGFloat = 44
    /// How far the knob follows the finger away from a notch before it gives.
    private static let detentGive: CGFloat = 0.3
    /// Further than this and a touch is a drag, not a tap.
    private static let tapSlop: CGFloat = 4
    /// The Android knob's spring: stiffness 900, damping ratio 0.45.
    private static var knobSpring: Animation {
        .spring(response: 0.21, dampingFraction: 0.45)
    }

    @Environment(Settings.self) private var settings
    @Environment(\.palette) private var palette
    @Environment(\.detentClick) private var detentClick

    /// The knob's place in notches, between them while dragged.
    @State private var knob: CGFloat = 0
    @State private var dragStartKnob: CGFloat?

    private var speeds: [Float] { Settings.playSpeeds }
    private var lastNotch: Int { speeds.count - 1 }

    private var chosenNotch: Int {
        speeds.indices.min { abs(speeds[$0] - settings.playSpeed) < abs(speeds[$1] - settings.playSpeed) } ?? 0
    }

    var body: some View {
        GeometryReader { geometry in
            let notches = FaderNotches(width: geometry.size.width, count: speeds.count)
            let art = VarispeedArt(knob: knob, chosen: chosenNotch, speeds: speeds, palette: palette)
            Canvas { context, size in art.draw(in: context, size: size, notches: notches) }
                .contentShape(Rectangle())
                .gesture(slide(notches))
        }
        .frame(height: Self.height)
        .onAppear { knob = CGFloat(chosenNotch) }
        .onChange(of: chosenNotch) { _, notch in
            guard dragStartKnob == nil else { return }
            withAnimation(Self.knobSpring) { knob = CGFloat(notch) }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Playback speed"))
        .accessibilityValue(Text(verbatim: VarispeedArt.mark(speeds[chosenNotch]) + "×"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(min(chosenNotch + 1, lastNotch))
            case .decrement: select(max(chosenNotch - 1, 0))
            @unknown default: break
            }
        }
    }

    private func slide(_ notches: FaderNotches) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let start = dragStartKnob ?? knob
                dragStartKnob = start
                guard abs(drag.translation.width) > Self.tapSlop else { return }
                let raw = min(max(start + drag.translation.width / notches.step, 0), CGFloat(lastNotch))
                let near = Int(raw.rounded())
                select(near)
                knob = CGFloat(near) + (raw - CGFloat(near)) * Self.detentGive
            }
            .onEnded { drag in
                dragStartKnob = nil
                let notch = abs(drag.translation.width) > Self.tapSlop ? Int(knob.rounded()) : notches.nearest(to: drag.location.x)
                select(notch)
                withAnimation(Self.knobSpring) { knob = CGFloat(notch) }
            }
    }

    private func select(_ notch: Int) {
        guard notch != chosenNotch, speeds.indices.contains(notch) else { return }
        settings.playSpeed = speeds[notch]
        detentClick()
    }
}
