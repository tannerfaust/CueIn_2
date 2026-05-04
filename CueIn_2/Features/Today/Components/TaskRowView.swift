import SwiftUI

// MARK: - TaskRowView
/// Clean task row. Neutral checkbox, no colored badges.

struct TaskRowView: View {
    let task: DayTask
    let onToggle: () -> Void

    @State private var animateCheck = false

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
            Menu {
                statusMenuButtons
            } label: {
                checkbox(status: plannerTask?.status)
            }
            .menuStyle(.borderlessButton)
            .cueInMenuInteractionStability()
        } else {
            Button(action: toggleFallback) {
                checkbox(status: nil)
            }
            .buttonStyle(.plain)
        }
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

    @ViewBuilder
    private var statusMenuButtons: some View {
        if task.isCompleted {
            Button(action: {}) {
                statusMenuRow(
                    icon: TaskStatus.completed.icon,
                    title: TaskStatus.completed.label,
                    isSelected: true
                )
            }
            .disabled(true)

            Divider()

            ForEach(TaskStatus.executionPoolOpenStatuses, id: \.self) { status in
                Button {
                    applyStatus(status)
                } label: {
                    statusMenuRow(
                        icon: status.icon,
                        title: status.reopenFromDoneMenuTitle(),
                        isSelected: false
                    )
                }
            }
        } else {
            ForEach(TaskStatus.executionPoolOpenStatuses, id: \.self) { status in
                Button {
                    applyStatus(status)
                } label: {
                    statusMenuRow(
                        icon: status.icon,
                        title: status.label,
                        isSelected: plannerTask?.status == status
                    )
                }
            }

            Divider()

            Button {
                applyStatus(.completed)
            } label: {
                statusMenuRow(
                    icon: TaskStatus.completed.icon,
                    title: TaskStatus.completed.label,
                    isSelected: false
                )
            }
        }
    }

    private func statusMenuRow(icon: String, title: String, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CueInColors.textSecondary)
                .frame(width: 20, alignment: .center)
            Text(title)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(CueInColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CueInColors.textSecondary)
            }
        }
    }

    private var plannerTask: TaskItem? {
        guard let id = task.plannerTaskItemID else { return nil }
        return TasksStore.shared.tasks.first { $0.id == id }
    }

    private func applyStatus(_ status: TaskStatus) {
        guard let id = task.plannerTaskItemID else {
            toggleFallback()
            return
        }
        TasksStore.shared.setTodayTodoTaskStatus(id: id, status: status)
        TodayViewModel.shared.syncExecutionTimelineAfterExternalTaskEdit()
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
