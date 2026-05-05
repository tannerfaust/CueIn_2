import SwiftUI

// MARK: - CueInTaskStatusPopoverContent
/// Single shared status picker used from To-do rows, schedule-linked rows, and the task editor.
/// Matches the popover layout from the To-do checkbox (not the compact `Menu` chrome).

struct CueInTaskStatusPopoverContent: View {
    let selection: TaskStatus
    let onSelect: (TaskStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(TaskStatus.statusPickerOrdering, id: \.self) { status in
                Button {
                    onSelect(status)
                } label: {
                    row(icon: status.icon, title: status.label, isSelected: selection == status)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(minWidth: 230, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .presentationCompactAdaptation(.popover)
    }

    private func row(icon: String, title: String, isSelected: Bool) -> some View {
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
