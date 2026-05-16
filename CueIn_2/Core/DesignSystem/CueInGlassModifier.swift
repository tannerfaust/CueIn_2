import SwiftUI

// MARK: - Unified Liquid Glass Modifier (iOS 26)
/// Single source of truth for glass effects across the app.
/// Replaces: TodayCapsuleGlassModifier, TodayCircleGlassModifier,
/// CueInCircleGlassModifier, TabBarGlassModifier, CircularGlassButtonModifier,
/// MenuGlassBackground, ScheduleBlockGlassDesignModifier (shape portion).

// MARK: - Shape Abstraction

enum CueInGlassShape: Equatable {
    case circle
    case capsule
    case roundedRect(cornerRadius: CGFloat)
}

// MARK: - Unified Modifier

struct CueInGlassModifier: ViewModifier {
    let shape: CueInGlassShape
    var tint: Color = CueInColors.activeHint
    var interactive: Bool = true
    var showsBorder: Bool = false
    var borderColor: Color = CueInColors.cardBorder
    var borderWidth: CGFloat = 0.5
    /// Drop shadow parameters; pass nil for no shadow.
    var shadow: CueInGlassShadow? = nil

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            glassContent(content)
        } else {
            fallbackContent(content)
        }
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private func glassContent(_ content: Content) -> some View {
        let base = applyGlassEffect(to: content)
        applyDecoration(to: base)
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private func applyGlassEffect(to content: Content) -> some View {
        switch shape {
        case .circle:
            if interactive {
                content.glassEffect(.regular.tint(tint).interactive(), in: .circle)
            } else {
                content.glassEffect(.regular.tint(tint), in: .circle)
            }
        case .capsule:
            if interactive {
                content.glassEffect(.regular.tint(tint).interactive(), in: .capsule)
            } else {
                content.glassEffect(.regular.tint(tint), in: .capsule)
            }
        case .roundedRect(let radius):
            if interactive {
                content.glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: radius))
            } else {
                content.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: radius))
            }
        }
    }

    @ViewBuilder
    private func fallbackContent(_ content: Content) -> some View {
        let base = applyFallbackMaterial(to: content)
        applyDecoration(to: base)
    }

    @ViewBuilder
    private func applyFallbackMaterial(to content: Content) -> some View {
        switch shape {
        case .circle:
            content.background(.regularMaterial, in: Circle())
        case .capsule:
            content.background(.regularMaterial, in: Capsule(style: .continuous))
        case .roundedRect(let radius):
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }

    @ViewBuilder
    private func applyDecoration<V: View>(to base: V) -> some View {
        if showsBorder {
            base
                .overlay { borderOverlay }
                .ifLet(shadow) { view, s in
                    view.shadow(color: s.color, radius: s.radius, x: s.x, y: s.y)
                }
        } else if let shadow {
            base.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
        } else {
            base
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        switch shape {
        case .circle:
            Circle()
                .strokeBorder(borderColor, lineWidth: borderWidth)
        case .capsule:
            Capsule(style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        case .roundedRect(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        }
    }
}

struct CueInGlassShadow: Equatable {
    var color: Color = Color.black.opacity(0.24)
    var radius: CGFloat = 18
    var x: CGFloat = 0
    var y: CGFloat = 8
}

// MARK: - Convenience Extensions

extension View {
    /// Applies the unified CueIn glass treatment.
    func cueInGlass(
        _ shape: CueInGlassShape,
        tint: Color = CueInColors.activeHint,
        interactive: Bool = true,
        showsBorder: Bool = false,
        borderColor: Color = CueInColors.cardBorder,
        borderWidth: CGFloat = 0.5,
        shadow: CueInGlassShadow? = nil
    ) -> some View {
        modifier(CueInGlassModifier(
            shape: shape,
            tint: tint,
            interactive: interactive,
            showsBorder: showsBorder,
            borderColor: borderColor,
            borderWidth: borderWidth,
            shadow: shadow
        ))
    }

    /// Conditional transform helper — applies a transform only when the optional is non-nil.
    @ViewBuilder
    func ifLet<T, Result: View>(_ value: T?, transform: (Self, T) -> Result) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}
