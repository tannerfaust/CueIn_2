import SwiftUI

// MARK: - Liquid Glass toolbar circles (iOS 26)
/// Native `glassEffect` only — no extra strokes or highlight overlays (those read as “whitish rings” on small 38pt circles).

enum CueInLiquidGlassToolbarRole {
    case close
    case save
}

struct CueInLiquidGlassToolbarIconButton: View {

    let role: CueInLiquidGlassToolbarRole
    let action: () -> Void
    var isEnabled: Bool = true

    private let diameter: CGFloat = 42

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: role == .close ? "xmark" : "checkmark")
                    .font(.system(size: role == .close ? 16 : 18, weight: .semibold))
                    .foregroundStyle(iconForeground)
            }
            .frame(width: diameter, height: diameter)
            .modifier(LiquidGlassToolbarCircleModifier(role: role))
            .contentShape(Circle())
        }
        .buttonStyle(ToolbarLiquidGlassPressStyle())
        /// Keeps the nav bar from vertically compressing the circle (flat-top clipping).
        .fixedSize(horizontal: true, vertical: true)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(role == .close ? "Close" : "Save")
    }

    private var iconForeground: Color {
        switch role {
        case .close:
            return Color.white.opacity(0.94)
        case .save:
            return Color(hex: 0xD6EDFF)
        }
    }
}

// MARK: - Native glass only

private struct LiquidGlassToolbarCircleModifier: ViewModifier {
    let role: CueInLiquidGlassToolbarRole

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular
                        .tint(glassTint)
                        .interactive(),
                    in: .circle
                )
                /// Tight shadow so the bar doesn’t clip the glow (nav toolbar clips aggressively).
                .shadow(color: Color.black.opacity(0.22), radius: 5, x: 0, y: 3)
        } else {
            content
                .background(fallbackFill, in: Circle())
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
        }
    }

    /// Smoky charcoal (close) vs saturated blue (save) — same family as ``FloatingCircularGlassIconButton``.
    private var glassTint: Color {
        switch role {
        case .close:
            return Color.white.opacity(0.14)
        case .save:
            /// System-style saturated blue with enough opacity to read as a real blue button.
            return Color(hex: 0x0A84FF).opacity(0.82)
        }
    }

    private var fallbackFill: LinearGradient {
        switch role {
        case .close:
            return LinearGradient(
                colors: [
                    Color(hex: 0x3D3D42),
                    Color(hex: 0x1C1C1F),
                    Color(hex: 0x101012),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .save:
            return LinearGradient(
                colors: [
                    Color(hex: 0x409CFF),
                    Color(hex: 0x007AFF),
                    Color(hex: 0x0051D5),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Press

private struct ToolbarLiquidGlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - iOS 26 toolbar: drop system “shared glass” behind items

extension ToolbarContent {
    /// Navigation bar items get an extra system Liquid Glass layer; combined with our own `glassEffect` it reads as a double ring. Hide it for custom glass controls.
    @ToolbarContentBuilder
    func cueInHideSharedToolbarGlassBackground() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
