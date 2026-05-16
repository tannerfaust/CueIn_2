import SwiftUI

// MARK: - ExecutionTaskEditorSheet

struct ExecutionTaskEditorSheet: View {
    let task: ExecutionTaskCard
    let onSave: (ExecutionTaskCard) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ExecutionTaskCard
    @State private var showingDelete = false
    @FocusState private var titleFocused: Bool

    init(
        task: ExecutionTaskCard,
        onSave: @escaping (ExecutionTaskCard) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.task = task
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: task)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CueInSpacing.lg) {
                    titleCard
                    timingCard
                    typeCard
                    deleteCard
                }
                .padding(.top, CueInSpacing.base)
                .padding(.bottom, CueInSpacing.huge)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(CueInColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(CueInColors.textSecondary)
                }
                ToolbarItem(placement: .principal) {
                    Text("Edit Task")
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(canSave ? CueInColors.accentFocus : CueInColors.textTertiary)
                    .disabled(!canSave)
                }
            }
            .alert("Delete task?", isPresented: $showingDelete) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("This removes it from the execution timeline.")
            }
        }
        .cueInPreferredColorScheme()
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var titleCard: some View {
        VStack(spacing: 0) {
            TextField("What needs doing?", text: $draft.title, axis: .vertical)
                .font(CueInTypography.title)
                .foregroundStyle(CueInColors.textPrimary)
                .tint(CueInColors.accentFocus)
                .focused($titleFocused)
                .padding(.horizontal, CueInSpacing.base)
                .padding(.vertical, CueInSpacing.base)

            Divider().background(CueInColors.divider)

            Toggle(isOn: $draft.isCompleted) {
                HStack(spacing: 8) {
                    Image(systemName: draft.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(draft.isCompleted ? CueInColors.success : CueInColors.textSecondary)
                    Text(draft.isCompleted ? "Completed" : "Open")
                        .font(CueInTypography.body)
                        .foregroundStyle(CueInColors.textPrimary)
                }
            }
            .tint(CueInColors.accentFocus)
            .padding(.horizontal, CueInSpacing.base)
            .padding(.vertical, 10)
        }
        .timelineEditorCard()
    }

    private var timingCard: some View {
        VStack(spacing: 0) {
            DatePicker(
                "Start",
                selection: $draft.startDate,
                displayedComponents: [.hourAndMinute]
            )
            .datePickerStyle(.compact)
            .tint(CueInColors.accentFocus)
            .foregroundStyle(CueInColors.textPrimary)
            .padding(.horizontal, CueInSpacing.base)
            .padding(.vertical, 12)

            Divider().background(CueInColors.divider)

            editorPickerRow(icon: "clock", title: "Duration") {
                Menu {
                    ForEach([5, 10, 15, 20, 25, 30, 45, 60, 90, 120], id: \.self) { minutes in
                        Button {
                            draft.durationMinutes = minutes
                        } label: {
                            Text("\(minutes) min")
                        }
                    }
                } label: {
                    pickerValue("\(draft.durationMinutes) min")
                }
            }
        }
        .timelineEditorCard()
    }

    private var typeCard: some View {
        VStack(spacing: 0) {
            editorPickerRow(icon: draft.blockType.icon, title: "Type", iconColor: draft.blockType.accent) {
                Menu {
                    ForEach(BlockType.allCases) { type in
                        Button {
                            draft.blockType = type
                            draft.blockTypeLabel = type.label
                            draft.lane = ExecutionLane.suggested(for: type)
                        } label: {
                            Label(type.label, systemImage: type.icon)
                        }
                    }
                } label: {
                    pickerValue(draft.blockType.label)
                }
            }

            Divider().background(CueInColors.divider)

            Toggle(isOn: $draft.isPrimary) {
                editorLabel(icon: "flag.fill", title: "Priority", iconColor: CueInColors.accentFocus)
            }
            .tint(CueInColors.accentFocus)
            .padding(.horizontal, CueInSpacing.base)
            .padding(.vertical, 12)

            Divider().background(CueInColors.divider)

            Toggle(isOn: $draft.isRepeating) {
                editorLabel(icon: "arrow.triangle.2.circlepath", title: "Repeating")
            }
            .tint(CueInColors.accentFocus)
            .padding(.horizontal, CueInSpacing.base)
            .padding(.vertical, 12)
        }
        .timelineEditorCard()
    }

    private var deleteCard: some View {
        Button(role: .destructive) {
            showingDelete = true
        } label: {
            HStack {
                Image(systemName: "trash.fill")
                Text("Delete from timeline")
                Spacer()
            }
            .font(CueInTypography.bodyMedium)
            .foregroundStyle(CueInColors.danger)
            .padding(CueInSpacing.base)
        }
        .buttonStyle(.plain)
        .timelineEditorCard()
    }

    private func editorPickerRow<Content: View>(
        icon: String,
        title: String,
        iconColor: Color = CueInColors.textSecondary,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: CueInSpacing.md) {
            editorLabel(icon: icon, title: title, iconColor: iconColor)
            Spacer(minLength: CueInSpacing.md)
            content()
        }
        .padding(.horizontal, CueInSpacing.base)
        .padding(.vertical, 12)
    }

    private func editorLabel(icon: String, title: String, iconColor: Color = CueInColors.textSecondary) -> some View {
        HStack(spacing: CueInSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 20)
            Text(title)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textPrimary)
        }
    }

    private func pickerValue(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textSecondary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(CueInColors.textTertiary)
        }
    }
}

private extension View {
    func timelineEditorCard() -> some View {
        self
            .background(CueInColors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                    .strokeBorder(CueInColors.cardBorder, lineWidth: 0.5)
            )
            .padding(.horizontal, CueInSpacing.screenHorizontal)
    }
}
