import SwiftUI

// MARK: - CueInCard
/// Clean, dark, rounded card. Subtle border, no flashy edges.

struct CueInCard<Content: View>: View {
    let surface: Color
    let padding: CGFloat
    let cornerRadius: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        surface: Color = CueInColors.surfacePrimary,
        padding: CGFloat = CueInSpacing.cardPadding,
        cornerRadius: CGFloat = CueInSpacing.cardRadius,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.surface = surface
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(CueInColors.cardBorder, lineWidth: 0.5)
            )
    }
}
