import SwiftUI

// MARK: - TimelineActionSheet
/// Bottom sheet for the floating + in task-led mode — add-only; run controls live on the lightning button.

struct TimelineActionSheet: View {

    let onAddTask: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        CueInBottomSheet(title: "Add", onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                SheetActionRow(
                    icon: "checkmark.circle.fill",
                    title: "New Task",
                    subtitle: "Add a task to today's execution timeline"
                ) {
                    onAddTask()
                }
            }
        }
    }
}

#Preview {
    ZStack {
        CueInColors.background.ignoresSafeArea()
        TimelineActionSheet(onAddTask: {}, onDismiss: {})
    }
    .cueInPreferredColorScheme()
}
