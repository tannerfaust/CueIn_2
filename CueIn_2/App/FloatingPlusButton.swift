import SwiftUI

// MARK: - FloatingPlusButton
/// Circular add button that uses native Liquid Glass on iOS 26.

struct FloatingPlusButton: View {
    let action: () -> Void
    @State private var feedbackTrigger = false

    var body: some View {
        FloatingCircularGlassIconButton(
            systemImage: "plus",
            iconSize: CueInLayout.fabPlusIconSize,
            diameter: CueInLayout.fabPlusDiameter,
            glassTint: Color.white.opacity(0.14),
            iconColor: .white,
            sensoryTrigger: $feedbackTrigger,
            action: action
        )
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
            action: action
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
    let action: () -> Void

    var body: some View {
        Button {
            sensoryTrigger.toggle()
            action()
        } label: {
            ZStack {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .frame(width: diameter, height: diameter)
        }
        .buttonStyle(PressScaleStyle())
        .contentShape(Circle())
        .modifier(CircularGlassButtonModifier(glassTint: glassTint))
        .sensoryFeedback(.impact, trigger: sensoryTrigger)
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

private struct CircularGlassButtonModifier: ViewModifier {
    var glassTint: Color = Color.white.opacity(0.14)

    func body(content: Content) -> some View {
        content
            .cueInGlass(
                .circle,
                tint: glassTint,
                showsBorder: true,
                borderColor: Color.white.opacity(0.18),
                borderWidth: 0.75,
                shadow: CueInGlassShadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 8)
            )
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        FloatingPlusButton {}
    }
    .preferredColorScheme(.dark)
}
