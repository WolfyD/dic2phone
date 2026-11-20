import SwiftUI

/// The ribbed chrome nub that rides in a slide switch's slot.
struct SlideNub: View {
    private static let ribs = 3

    let face1: Color
    let face2: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            RoundedRectangle(cornerRadius: 2)
                .fill(LinearGradient(colors: [face1, face2], startPoint: .top, endPoint: .bottom))
                .overlay {
                    ForEach(1 ... Self.ribs, id: \.self) { rib in
                        Rectangle()
                            .fill(.black.opacity(0.35))
                            .frame(width: 1)
                            .padding(.vertical, 2)
                            .position(x: width * CGFloat(rib) / CGFloat(Self.ribs + 1), y: geometry.size.height / 2)
                    }
                }
        }
    }
}
