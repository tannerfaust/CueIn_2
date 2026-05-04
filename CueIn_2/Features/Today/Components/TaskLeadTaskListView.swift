import SwiftUI

// MARK: - TaskLeadTaskListView

struct TaskLeadTaskListView: View {
    let sections: [TaskLeadTaskSection]
    let onToggleTask: (UUID, UUID) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: CueInSpacing.md) {
            ForEach(sections) { section in
                CueInCard {
                    VStack(alignment: .leading, spacing: CueInSpacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                                .font(CueInTypography.captionMedium)
                                .foregroundStyle(CueInColors.textPrimary)

                            if let subtitle = section.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(CueInTypography.micro)
                                    .foregroundStyle(CueInColors.textTertiary)
                            }
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 {
                                    Rectangle()
                                        .fill(CueInColors.divider)
                                        .frame(height: 0.5)
                                        .padding(.vertical, CueInSpacing.sm)
                                }

                                TaskLeadTaskRowView(item: item) {
                                    onToggleTask(item.blockID, item.id)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }
}

// MARK: - TaskLeadTaskRowView

private struct TaskLeadTaskRowView: View {
    let item: TaskLeadTaskItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: CueInSpacing.md) {
                checkbox

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.task.title)
                        .font(item.task.isPrimary ? CueInTypography.bodyMedium : CueInTypography.body)
                        .foregroundStyle(item.isCompleted ? CueInColors.textTertiary : CueInColors.textPrimary)
                        .strikethrough(item.isCompleted, color: CueInColors.textTertiary)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        Text(item.blockTitle)
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(CueInColors.surfaceSecondary)
                            .clipShape(Capsule())

                        Text(item.blockTypeLabel)
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textTertiary)

                        if item.task.isRepeating {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(CueInColors.textTertiary)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .opacity(item.isCompleted ? 0.72 : 1)
    }

    private var checkbox: some View {
        CueInTaskStatusCheckbox(
            isCompleted: item.isCompleted,
            workflowStatus: nil,
            diameter: 20
        )
        .padding(.top, 2)
    }
}
