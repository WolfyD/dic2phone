import SwiftUI

/// The compartment's thin hinged lid with its finger notch. Opening, it squashes up towards its
/// hinge, turns over to its darker underside, and drops back down.
struct CompartmentLid: View, Animatable {
    private static let height: CGFloat = 22

    /// 0 closed, 1 open.
    var flip: CGFloat

    @Environment(\.palette) private var palette

    var animatableData: CGFloat {
        get { flip }
        set { flip = newValue }
    }

    private var showsUnderside: Bool {
        flip > 0.5
    }

    var body: some View {
        Canvas { context, size in drawLid(in: &context, size: size) }
            .overlay(alignment: .leading) { label }
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .scaleEffect(x: 1, y: max(abs(1 - 2 * flip), 0.08), anchor: showsUnderside ? .bottom : .top)
    }

    private var label: some View {
        Text(verbatim: (showsUnderside ? Glyph.lidOpen : Glyph.lidClosed) + "  " + String(localized: "MORE CONTROLS"))
            .font(DeckFont.monoBold.fixed(9))
            .tracking(1.5)
            .foregroundStyle(palette.dim)
            .lineLimit(1)
            .padding(.leading, 12)
    }

    private func drawLid(in context: inout GraphicsContext, size: CGSize) {
        let lid = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4)
        context.fill(lid, with: .linearGradient(
            Gradient(colors: faceColors),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height)
        ))
        context.stroke(lid, with: .color(.black.opacity(0.55)), lineWidth: 1)

        let hingeY = showsUnderside ? size.height - 2 : 2
        var hinge = Path()
        hinge.move(to: CGPoint(x: 6, y: hingeY))
        hinge.addLine(to: CGPoint(x: size.width - 6, y: hingeY))
        context.stroke(hinge, with: .color(.black.opacity(0.4)), lineWidth: 1)

        let notch = CGSize(width: 46, height: 6)
        let notchRect = CGRect(
            origin: CGPoint(x: (size.width - notch.width) / 2, y: showsUnderside ? 0 : size.height - notch.height),
            size: notch
        )
        context.fill(Path(roundedRect: notchRect, cornerRadius: notch.height / 2), with: .color(.black.opacity(0.55)))
    }

    private var faceColors: [Color] {
        showsUnderside
            ? [palette.panel.mix(with: .black, by: 0.45), palette.panel.mix(with: .black, by: 0.25)]
            : [palette.panel.mix(with: .white, by: 0.14), palette.panel.mix(with: .black, by: 0.1)]
    }
}
