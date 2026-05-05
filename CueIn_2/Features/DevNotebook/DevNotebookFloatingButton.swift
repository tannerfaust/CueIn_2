import SwiftUI

// MARK: - DevNotebookFloatingButton

/// Bottom-leading capture control; mirrors glass treatment from ``FloatingPlusButton``.
struct DevNotebookFloatingButton: View {
    let action: () -> Void
    @State private var feedbackTrigger = false

    private let diameter: CGFloat = 52
    private let iconSize: CGFloat = 19

    var body: some View {
        Button {
            feedbackTrigger.toggle()
            action()
        } label: {
            Image(systemName: "note.text.badge.plus")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
                .cueInGlass(
                    .circle,
                    tint: Color(red: 0.45, green: 0.72, blue: 1.0).opacity(0.22),
                    showsBorder: true,
                    borderColor: Color.white.opacity(0.18),
                    borderWidth: 0.75,
                    shadow: CueInGlassShadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 8)
                )
        }
        .buttonStyle(DevNotebookGlassPressStyle())
        .sensoryFeedback(.impact, trigger: feedbackTrigger)
        .accessibilityLabel("Dev notebook capture")
        .accessibilityHint("Add an idea or bug note with screen context")
    }
}

// MARK: - Press style

private struct DevNotebookGlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}
