import SwiftUI

// MARK: - AddItemSheetView
/// Clean, neutral bottom sheet for adding items.

struct AddItemSheetView: View {
    let onChangeFormula: (() -> Void)?
    let onAddBlock: () -> Void
    let onAddTask: () -> Void
    let onAddRoutineBlock: () -> Void
    let onAddQuickItem: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        CueInBottomSheet(title: "Add to Today", onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                if let onChangeFormula {
                    SheetActionRow(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Change Schedule",
                        subtitle: "Switch today’s framework"
                    ) { onChangeFormula() }
                }

                SheetActionRow(
                    icon: "rectangle.stack.fill",
                    title: "Add Block",
                    subtitle: "Create a new time block for your day"
                ) { onAddBlock() }

                SheetActionRow(
                    icon: "checkmark.circle.fill",
                    title: "Add Task",
                    subtitle: "Add a task to an existing block"
                ) { onAddTask() }

                SheetActionRow(
                    icon: "repeat",
                    title: "Add Routine Block",
                    subtitle: "Insert a repeatable routine"
                ) { onAddRoutineBlock() }

                SheetActionRow(
                    icon: "bolt.fill",
                    title: "Add Quick Item",
                    subtitle: "A small task or mini-block"
                ) { onAddQuickItem() }
            }
        }
    }
}

struct ScheduleQuickAddTaskSheet: View {
    let blocks: [DayBlock]
    let onAdd: (UUID, String) -> Void
    let onCancel: () -> Void

    @State private var selectedBlockID: UUID?
    @State private var title = ""

    private var candidateBlocks: [DayBlock] {
        blocks.filter { $0.state != .completed && $0.state != .skipped }
    }

    private var selectedBlock: DayBlock? {
        guard let selectedBlockID else { return candidateBlocks.first }
        return candidateBlocks.first { $0.id == selectedBlockID } ?? candidateBlocks.first
    }

    var body: some View {
        CueInBottomSheet(title: "Add task to block", onDismiss: onCancel) {
            VStack(alignment: .leading, spacing: CueInSpacing.md) {
                if candidateBlocks.isEmpty {
                    Text("Create a block first, then add tasks to it.")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    blockPicker
                    taskTitleField
                    actionRow
                }
            }
            .onAppear {
                selectedBlockID = selectedBlock?.id
            }
        }
    }

    private var blockPicker: some View {
        Menu {
            ForEach(candidateBlocks) { block in
                Button {
                    selectedBlockID = block.id
                } label: {
                    Label(block.title, systemImage: block.type.icon)
                }
            }
        } label: {
            HStack(spacing: CueInSpacing.md) {
                Image(systemName: selectedBlock?.type.icon ?? "rectangle.stack")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        selectedBlock.map {
                            CueInColors.resolvedTimelineAccent(blockType: $0.type, hex: $0.timelineAccentHex)
                        } ?? CueInColors.textSecondary
                    )
                    .frame(width: 28, height: 28)
                    .background(CueInColors.surfaceTertiary.opacity(0.48), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedBlock?.title ?? "Choose block")
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                        .lineLimit(1)
                    Text(selectedBlock?.timeRangeLabel ?? "Target block")
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                        .monospacedDigit()
                }

                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CueInColors.textTertiary)
            }
            .padding(CueInSpacing.md)
            .background(CueInColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .cueInMenuInteractionStability()
    }

    private var taskTitleField: some View {
        TextField("Task name", text: $title)
            .font(CueInTypography.bodyMedium)
            .textInputAutocapitalization(.sentences)
            .padding(CueInSpacing.md)
            .background(CueInColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
            .foregroundStyle(CueInColors.textPrimary)
    }

    private var actionRow: some View {
        HStack(spacing: CueInSpacing.md) {
            Button("Cancel", action: onCancel)
                .font(CueInTypography.bodyMedium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, CueInSpacing.md)
                .foregroundStyle(CueInColors.textSecondary)

            Button("Add") {
                guard let id = selectedBlock?.id else { return }
                onAdd(id, title)
            }
            .font(CueInTypography.bodyMedium)
            .frame(maxWidth: .infinity)
            .padding(.vertical, CueInSpacing.md)
            .foregroundStyle(Color.black.opacity(0.86))
            .background(
                CueInColors.accentFocus,
                in: RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
            )
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedBlock == nil)
            .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedBlock == nil ? 0.45 : 1)
        }
    }
}
