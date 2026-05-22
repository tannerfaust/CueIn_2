import SwiftUI

// MARK: - TaskRowView
/// Clean task row. Neutral checkbox, no colored badges.
///
/// **Note:** The status control uses a Button + popover instead of
/// `Menu { ... } .menuStyle(.borderlessButton)`. The borderless menu style
/// forces a `UIContextMenuInteraction` UIKit bridge that emits runtime
/// warnings on iOS 26. The popover approach is native SwiftUI and silent.

struct TaskRowView: View {
    let task: DayTask
    let onToggle: () -> Void

    @State private var animateCheck = false
    @State private var isStatusPopoverPresented = false

    var body: some View {
        HStack(spacing: CueInSpacing.md) {
            statusControl

            Button(action: toggleFallback) {
                HStack(spacing: CueInSpacing.md) {
                    Text(task.title)
                        .font(task.isPrimary ? CueInTypography.bodyMedium : CueInTypography.body)
                        .foregroundStyle(
                            task.isCompleted ? CueInColors.textTertiary : CueInColors.textPrimary
                        )
                        .strikethrough(task.isCompleted, color: CueInColors.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    if task.isRepeating {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10))
                            .foregroundStyle(CueInColors.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, CueInSpacing.xs)
    }

    @ViewBuilder
    private var statusControl: some View {
        if task.plannerTaskItemID != nil {
            Button {
                isStatusPopoverPresented = true
            } label: {
                checkbox(status: plannerTask?.status)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isStatusPopoverPresented) {
                CueInTaskStatusPopoverContent(selection: statusPickerSelection) { applyStatusAndClose($0) }
            }
        } else {
            Button(action: toggleFallback) {
                checkbox(status: nil)
            }
            .buttonStyle(.plain)
        }
    }

    private var statusPickerSelection: TaskStatus {
        if let s = plannerTask?.status { return s }
        return task.isCompleted ? .completed : .inbox
    }

    private func checkbox(status: TaskStatus?) -> some View {
        CueInTaskStatusCheckbox(
            isCompleted: task.isCompleted,
            workflowStatus: task.isCompleted ? nil : status,
            diameter: 20,
            completeScale: animateCheck ? 1.12 : 1
        )
        .frame(width: 28, height: 30)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.18), value: status)
        .animation(.easeInOut(duration: 0.15), value: task.isCompleted)
    }

    private var plannerTask: TaskItem? {
        guard let id = task.plannerTaskItemID else { return nil }
        return TasksStore.shared.tasks.first { $0.id == id }
    }

    private func applyStatusAndClose(_ status: TaskStatus) {
        isStatusPopoverPresented = false
        applyStatus(status)
    }

    private func applyStatus(_ status: TaskStatus) {
        guard let id = task.plannerTaskItemID else {
            toggleFallback()
            return
        }
        let willBeCompleted = status == .completed
        let shouldToggleBlockTask = willBeCompleted != task.isCompleted

        TasksStore.shared.setTodayTodoTaskStatus(id: id, status: status)

        if shouldToggleBlockTask {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                animateCheck = willBeCompleted
                onToggle()
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                animateCheck = false
            }
        } else {
            TodayViewModel.shared.syncExecutionTimelineAfterExternalTaskEdit()
        }
    }

    private func toggleFallback() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
            animateCheck = true
            onToggle()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            animateCheck = false
        }
    }
}
