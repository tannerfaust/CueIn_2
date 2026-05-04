import SwiftUI

/// Subtle Freeform-style dot grid for schedule screens; non-interactive.
struct CanvasDotsBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let spacing: CGFloat = 20
    private let dotDiameter: CGFloat = 2

    private var dotColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.065)
            : Color.black.opacity(0.055)
    }

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                var x = spacing * 0.5
                while x < size.width + spacing {
                    var y = spacing * 0.5
                    while y < size.height + spacing {
                        let r = dotDiameter * 0.5
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: dotDiameter, height: dotDiameter)),
                            with: .color(dotColor)
                        )
                        y += spacing
                    }
                    x += spacing
                }
            }
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    ZStack {
        CueInColors.background.ignoresSafeArea()
        CanvasDotsBackgroundView()
    }
    .preferredColorScheme(.dark)
}
