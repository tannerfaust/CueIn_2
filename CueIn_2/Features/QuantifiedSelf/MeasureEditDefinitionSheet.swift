import SwiftUI

// MARK: - MeasureEditDefinitionSheet

struct MeasureEditDefinitionSheet: View {
    @Bindable private var store = MeasureStore.shared
    @Bindable private var tasksStore = TasksStore.shared
    @Bindable private var goalStore = GoalStrategyStore.shared

    let definitionID: UUID
    let onDismiss: () -> Void

    @State private var draft: MeasureDefinition
    @State private var confirmDelete = false
    @State private var linkPicker: LinkPicker?

    private enum LinkPicker: String, Identifiable {
        case task
        case goal
        var id: String { rawValue }
    }

    init(definition: MeasureDefinition, onDismiss: @escaping () -> Void) {
        definitionID = definition.id
        self.onDismiss = onDismiss
        _draft = State(initialValue: definition)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Title", text: $draft.title)
                        .font(CueInTypography.body)
                } header: {
                    Text("Tracker")
                } footer: {
                    Text("Log type stays fixed so past days stay meaningful: \(draft.kind.pickerLabel)")
                        .font(CueInTypography.caption)
                }

                if draft.kind == .count {
                    Section("Daily target (optional)") {
                        Toggle("Show target", isOn: Binding(
                            get: { draft.dailyTarget != nil },
                            set: { on in
                                if on {
                                    if draft.dailyTarget == nil { draft.dailyTarget = 8 }
                                } else {
                                    draft.dailyTarget = nil
                                }
                            }
                        ))
                        if draft.dailyTarget != nil {
                            Stepper(
                                value: Binding(
                                    get: { draft.dailyTarget ?? 8 },
                                    set: { draft.dailyTarget = $0 }
                                ),
                                in: 1...99
                            ) {
                                Text("\(draft.dailyTarget ?? 8) per day")
                            }
                        }
                    }
                }

                Section("Links (optional)") {
                    linkRow(
                        title: "Related task",
                        value: taskTitle(for: draft.relatedTaskID),
                        clear: { draft.relatedTaskID = nil }
                    ) {
                        linkPicker = .task
                    }

                    linkRow(
                        title: "Related goal",
                        value: goalTitle(for: draft.relatedGoalID),
                        clear: { draft.relatedGoalID = nil }
                    ) {
                        linkPicker = .goal
                    }
                }

                Section {
                    Button("Delete tracker", role: .destructive) {
                        confirmDelete = true
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CueInColors.background.ignoresSafeArea())
            .navigationTitle("Edit tracker")
            .cueInNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                        .foregroundStyle(CueInColors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateDefinition(draft)
                        onDismiss()
                    }
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.accentFocus)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(item: $linkPicker) { pick in
                switch pick {
                case .task:
                    TaskLinkPickerSheet(
                        tasksStore: tasksStore,
                        selectedID: draft.relatedTaskID,
                        onPick: { draft.relatedTaskID = $0; linkPicker = nil },
                        onDismiss: { linkPicker = nil }
                    )
                case .goal:
                    GoalLinkPickerSheet(
                        goalStore: goalStore,
                        selectedID: draft.relatedGoalID,
                        onPick: { draft.relatedGoalID = $0; linkPicker = nil },
                        onDismiss: { linkPicker = nil }
                    )
                }
            }
            .confirmationDialog(
                "Delete this tracker?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    store.deleteDefinition(id: definitionID)
                    onDismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All logged values for this tracker will be removed from this device.")
            }
        }
    }

    private func taskTitle(for id: UUID?) -> String? {
        guard let id, let t = tasksStore.tasks.first(where: { $0.id == id }) else { return nil }
        return t.title
    }

    private func goalTitle(for id: UUID?) -> String? {
        guard let id, let g = goalStore.goal(id) else { return nil }
        return g.title
    }

    @ViewBuilder
    private func linkRow(title: String, value: String?, clear: @escaping () -> Void, pick: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CueInTypography.bodyMedium)
                if let value {
                    Text(value)
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                        .lineLimit(2)
                } else {
                    Text("None")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                }
            }
            Spacer()
            if value != nil {
                Button("Clear", action: clear)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
            }
            Button("Choose", action: pick)
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.accentFocus)
        }
    }
}

// MARK: - TaskLinkPickerSheet

private struct TaskLinkPickerSheet: View {
    @Bindable var tasksStore: TasksStore
    let selectedID: UUID?
    let onPick: (UUID?) -> Void
    let onDismiss: () -> Void

    @State private var query = ""

    private var rows: [TaskItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sorted = tasksStore.tasks.sorted { $0.updatedAt > $1.updatedAt }
        guard !q.isEmpty else { return Array(sorted.prefix(80)) }
        return sorted.filter { $0.title.lowercased().contains(q) }.prefix(80).map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Button("No linked task") {
                    onPick(nil)
                }
                .foregroundStyle(CueInColors.textPrimary)

                ForEach(rows) { task in
                    Button {
                        onPick(task.id)
                    } label: {
                        HStack {
                            Text(task.title)
                                .foregroundStyle(CueInColors.textPrimary)
                            Spacer()
                            if task.id == selectedID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(CueInColors.accentFocus)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CueInColors.background.ignoresSafeArea())
            .navigationTitle("Link task")
            .cueInNavigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search tasks")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                        .foregroundStyle(CueInColors.accentFocus)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
    }
}

// MARK: - GoalLinkPickerSheet

private struct GoalLinkPickerSheet: View {
    @Bindable var goalStore: GoalStrategyStore
    let selectedID: UUID?
    let onPick: (UUID?) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Button("No linked goal") {
                    onPick(nil)
                }
                .foregroundStyle(CueInColors.textPrimary)

                ForEach(goalStore.activeGoals) { goal in
                    Button {
                        onPick(goal.id)
                    } label: {
                        HStack {
                            Text(goal.title)
                                .foregroundStyle(CueInColors.textPrimary)
                            Spacer()
                            if goal.id == selectedID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(CueInColors.accentFocus)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CueInColors.background.ignoresSafeArea())
            .navigationTitle("Link goal")
            .cueInNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                        .foregroundStyle(CueInColors.accentFocus)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
    }
}
