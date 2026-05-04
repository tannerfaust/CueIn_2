import SwiftUI

// MARK: - CueInOverflowMenuGlyph
/// Shared overflow menu affordance for top chrome and task detail screens.

struct CueInOverflowMenuGlyph: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(CueInColors.textPrimary)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .modifier(CueInCircleGlassModifier())
            .accessibilityLabel("More")
    }
}

struct CueInCircleGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.cueInGlass(.circle)
    }
}

// MARK: - Menu interaction (UIKit bridge)

extension View {
    /// Keep as a no-op hook. The previous UIKit bridge modifier triggered noisy
    /// context-menu/reparenting warnings on newer iOS builds.
    @ViewBuilder
    func cueInMenuInteractionStability() -> some View {
        self
    }
}
