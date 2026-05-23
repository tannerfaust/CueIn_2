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
    /// Time block accent — tints the subtask rail when set.
    var blockAccent: Color? = nil
    let onToggle: () -> Void

    @State private var animateCheck = false
    @State private var isStatusPopoverPresented = false

    private var showsLinkedSubtaskPreview: Bool {
        guard let plannerTask else { return false }
        return !plannerTask.subtasks.isEmpty
    }

    var body: some View {
        HStack(alignment: showsLinkedSubtaskPreview ? .top : .center, spacing: CueInSpacing.md) {
            statusControl
                .padding(.top, showsLinkedSubtaskPreview ? 3 : 0)

            VStack(alignment: .leading, spacing: 0) {
                titleRow

                if let plannerTask, showsLinkedSubtaskPreview {
                    linkedSubtasksList(plannerTask)
                }
            }
        }
        .padding(.vertical, CueInSpacing.xs)
    }

    private var titleRow: some View {
        Button(action: toggleFallback) {
            HStack(alignment: .center, spacing: CueInSpacing.md) {
                Text(task.title)
                    .font(task.isPrimary ? CueInTypography.bodyMedium : CueInTypography.body)
                    .foregroundStyle(
                        task.isCompleted ? CueInColors.textTertiary : CueInColors.textPrimary
                    )
                    .strikethrough(task.isCompleted, color: CueInColors.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                if task.isRepeating {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(CueInColors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
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
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.18), value: status)
        .animation(.easeInOut(duration: 0.15), value: task.isCompleted)
    }

    private var plannerTask: TaskItem? {
        guard let id = task.plannerTaskItemID else { return nil }
        return TasksStore.shared.tasks.first { $0.id == id }
    }

    private var subtaskRailColor: Color {
        blockAccent ?? CueInColors.textSecondary
    }

    private func linkedSubtasksList(_ plannerTask: TaskItem) -> some View {
        let visibleSubtasks = visibleLinkedSubtasks(for: plannerTask)
        let remainingCount = max(0, plannerTask.subtasks.count - visibleSubtasks.count)
        let doneCount = plannerTask.subtasks.filter(\.isCompleted).count
        let totalCount = plannerTask.subtasks.count

        return VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(CueInColors.textPrimary.opacity(0.14))
                .frame(height: 1)
                .padding(.top, 10)
                .padding(.bottom, 8)

            HStack(alignment: .top, spacing: 0) {
                subtaskRail

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(visibleSubtasks) { subtask in
                        linkedSubtaskRow(subtask, taskID: plannerTask.id)
                    }

                    if remainingCount > 0 {
                        Text("+\(remainingCount) more")
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textSecondary)
                            .padding(.leading, 30)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtasksAccessibilityLabel(done: doneCount, total: totalCount))
    }

    private var subtaskRail: some View {
        Rectangle()
            .fill(subtaskRailColor.opacity(0.45))
            .frame(width: 2)
            .frame(maxHeight: .infinity, alignment: .top)
            .frame(width: 10)
            .padding(.top, 2)
    }

    private func subtasksAccessibilityLabel(done: Int, total: Int) -> String {
        if done == total, total > 0 {
            return "All \(total) subtasks complete"
        }
        return "\(done) of \(total) subtasks complete"
    }

    private func linkedSubtaskRow(_ subtask: TaskSubtask, taskID: UUID) -> some View {
        Button {
            TasksStore.shared.toggleTodayTodoSubtask(taskID: taskID, subtaskID: subtask.id)
            TodayViewModel.shared.syncExecutionTimelineAfterExternalTaskEdit()
        } label: {
            HStack(alignment: .center, spacing: 10) {
                subtaskCheckbox(for: subtask)

                Text(subtask.title)
                    .font(CueInTypography.body)
                    .foregroundStyle(
                        subtask.isCompleted ? CueInColors.textTertiary : CueInColors.textPrimary
                    )
                    .strikethrough(subtask.isCompleted, color: CueInColors.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(subtask.isCompleted ? "Completed, \(subtask.title)" : subtask.title)
        .accessibilityHint("Double tap to toggle")
    }

    @ViewBuilder
    private func subtaskCheckbox(for subtask: TaskSubtask) -> some View {
        let size: CGFloat = 18
        if subtask.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(CueInColors.success)
        } else {
            Image(systemName: "circle")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(CueInColors.textSecondary)
        }
    }

    private func visibleLinkedSubtasks(for plannerTask: TaskItem) -> [TaskSubtask] {
        let sorted = plannerTask.subtasks.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted && rhs.isCompleted
            }
            return lhs.createdAt < rhs.createdAt
        }
        return Array(sorted.prefix(5))
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
