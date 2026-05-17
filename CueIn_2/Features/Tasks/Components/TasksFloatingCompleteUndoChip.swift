import SwiftUI

// MARK: - TasksFloatingCompleteUndoChip
/// Compact glass undo control shown in the shell FAB column after completing a task from the Tasks list.

struct TasksFloatingCompleteUndoChip: View {
    let action: () -> Void
    @State private var feedbackTrigger = false

    var body: some View {
        Button {
            feedbackTrigger.toggle()
            action()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CueInColors.textPrimary)
                .frame(width: 44, height: 36)
                .contentShape(Capsule())
                .cueInGlass(
                    .capsule,
                    tint: CueInColors.activeHint.opacity(0.2),
                    showsBorder: true,
                    borderColor: CueInColors.cardBorder,
                    borderWidth: 0.75,
                    shadow: CueInGlassShadow(color: Color.black.opacity(0.22), radius: 14, x: 0, y: 6)
                )
        }
        .buttonStyle(TasksFloatingUndoPressStyle())
        .sensoryFeedback(.impact, trigger: feedbackTrigger)
        .accessibilityLabel("Undo complete")
        .accessibilityHint("Restores the task to how it was before you marked it done")
    }
}

private struct TasksFloatingUndoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        TasksFloatingCompleteUndoChip {}
    }
    .cueInPreferredColorScheme()
}
