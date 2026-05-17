import SwiftUI

#if os(iOS)

// MARK: - FloatingPlusButton
/// Circular add button that uses native Liquid Glass on iOS 26.

struct FloatingPlusButton: View {
    let onTap: () -> Void
    var onLongPress: (() -> Void)? = nil
    var accessibilityLabelText: String = "Add task"
    /// When `nil`, the hint reflects whether a long-press overflow menu is available.
    var accessibilityHintOverride: String? = nil
    @State private var feedbackTrigger = false

    private var resolvedAccessibilityHint: String {
        if let accessibilityHintOverride { return accessibilityHintOverride }
        return onLongPress == nil
            ? "Adds a new task"
            : "Tap to add a task. Hold for more actions for this screen."
    }

    var body: some View {
        FloatingCircularGlassIconButton(
            systemImage: "plus",
            iconSize: CueInLayout.fabPlusIconSize,
            diameter: CueInLayout.fabPlusDiameter,
            glassTint: CueInColors.activeHint,
            iconColor: CueInColors.textPrimary,
            sensoryTrigger: $feedbackTrigger,
            onTap: onTap,
            onLongPress: onLongPress
        )
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(resolvedAccessibilityHint)
    }
}

// MARK: - FloatingLightningButton
/// Smaller companion control for execution / day-run actions (stacked above the +).

struct FloatingLightningButton: View {
    let action: () -> Void
    @State private var feedbackTrigger = false

    private let boltTint = Color(red: 1.0, green: 0.86, blue: 0.35)

    var body: some View {
        FloatingCircularGlassIconButton(
            systemImage: "bolt.fill",
            iconSize: CueInLayout.fabExecutionIconSize,
            diameter: CueInLayout.fabExecutionDiameter,
            glassTint: boltTint.opacity(0.22),
            iconColor: boltTint,
            sensoryTrigger: $feedbackTrigger,
            onTap: action
        )
        .accessibilityLabel("Execution")
        .accessibilityHint("Open pause, resume, and run controls")
    }
}

// MARK: - Shared glass circle

private struct FloatingCircularGlassIconButton: View {
    let systemImage: String
    let iconSize: CGFloat
    let diameter: CGFloat
    let glassTint: Color
    let iconColor: Color
    @Binding var sensoryTrigger: Bool
    let onTap: () -> Void
    var onLongPress: (() -> Void)? = nil
    @State private var suppressNextTapAfterLongPress = false

    var body: some View {
        Group {
            if let longPress = onLongPress {
                coreButton
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.48)
                            .onEnded { _ in
                                suppressNextTapAfterLongPress = true
                                sensoryTrigger.toggle()
                                longPress()
                            }
                    )
            } else {
                coreButton
            }
        }
    }

    private var coreButton: some View {
        Button {
            if suppressNextTapAfterLongPress {
                suppressNextTapAfterLongPress = false
                return
            }
            sensoryTrigger.toggle()
            onTap()
        } label: {
            // Glass is applied INSIDE the button label so the ButtonStyle's
            // scaleEffect wraps the already-resolved glass shape. This prevents
            // the glass renderer from seeing a rectangular frame during the
            // press animation.
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
                .cueInGlass(
                    .circle,
                    tint: glassTint,
                    showsBorder: true,
                    borderColor: CueInColors.cardBorder,
                    borderWidth: 0.75,
                    shadow: CueInGlassShadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 8)
                )
        }
        .buttonStyle(GlassPressStyle())
        .sensoryFeedback(.impact, trigger: sensoryTrigger)
    }
}

// MARK: - Press style (scale only, no layout invalidation)

/// Applies a subtle scale-down on press. The glass effect is applied inside the
/// label so it doesn't re-resolve during the animation.
private struct GlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        FloatingPlusButton(onTap: {})
    }
    .cueInPreferredColorScheme()
}

#endif
