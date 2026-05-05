import SwiftUI

// MARK: - CueInOverflowMenuGlyph
/// Shared overflow menu affordance for top chrome and task detail screens.
///
/// **iOS 26 Liquid Glass:** Uses `.glassEffect()` on a background layer rather
/// than on the content itself. The glass shape is declared on a `Color.clear`
/// background positioned behind the icon, so the Menu's snapshot never captures
/// an intermediate rectangular glass frame. This eliminates the "flash to
/// square" artifact entirely.

struct CueInOverflowMenuGlyph: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(CueInColors.textPrimary)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .modifier(CueInStableGlassCircleModifier())
            .accessibilityLabel("More")
    }
}

// MARK: - Stable Glass Circle
/// Applies glass via a `.background` layer instead of directly on the content.
/// The glass is rendered on a separate `Color.clear` view that is pre-clipped
/// to a circle shape. Because the glass lives in the background layer, SwiftUI's
/// Menu snapshot system captures the icon + the already-resolved glass shape,
/// eliminating any intermediate rectangular flash.

struct CueInStableGlassCircleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background {
                    Circle()
                        .fill(.clear)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
        } else {
            content
                .background(.regularMaterial, in: Circle())
        }
    }
}

// MARK: - Stable Glass Capsule

struct CueInStableGlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background {
                    Capsule(style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
        } else {
            content
                .background(.regularMaterial, in: Capsule(style: .continuous))
        }
    }
}

// MARK: - Stable Glass RoundedRect

struct CueInStableGlassRoundedRectModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
                }
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

// MARK: - Legacy wrapper — delegates to unified system

struct CueInCircleGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.modifier(CueInStableGlassCircleModifier())
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
