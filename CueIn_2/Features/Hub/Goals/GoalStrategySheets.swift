import SwiftUI

// MARK: - Goal editor

struct GoalEditorSheet: View {
    let sheet: GoalStrategySheet
    let store: GoalStrategyStore
    let onCreated: (UUID) -> Void
    let onDismiss: () -> Void

    @State private var title: String
    @State private var description: String
    @State private var status: GoalStatus
    @State private var hasTargetDate: Bool
    @State private var targetDate: Date
    @State private var showDeleteAlert = false
    @FocusState private var titleFocused: Bool

    private let template: GoalTemplate?

    init(
        sheet: GoalStrategySheet,
        store: GoalStrategyStore,
        onCreated: @escaping (UUID) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.sheet = sheet
        self.store = store
        self.onCreated = onCreated
        self.onDismiss = onDismiss

        var existing: Goal?
        var selectedTemplate: GoalTemplate?

        switch sheet {
        case .editGoal(let id):
            existing = store.goal(id)
        case .createGoal(let templateID):
            if let templateID {
                selectedTemplate = GoalTemplate.library.first { $0.id == templateID }
            }
        default:
            break
        }

        template = selectedTemplate

        _title = State(initialValue: existing?.title ?? selectedTemplate?.title ?? "")
        _description = State(initialValue: existing?.description ?? selectedTemplate?.description ?? "")
        _status = State(initialValue: existing?.status ?? .active)
        _hasTargetDate = State(initialValue: existing?.targetDate != nil)
        _targetDate = State(initialValue: existing?.targetDate ?? Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date())
    }

    private var isEditing: Bool {
        if case .editGoal = sheet { return true }
        return false
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Goal Name", text: $title)
                        .focused($titleFocused)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section {
                    Picker("Status", selection: $status) {
                        ForEach(GoalStatus.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    
                    Toggle("Target Date", isOn: $hasTargetDate.animation())
                    
                    if hasTargetDate {
                        DatePicker("Target", selection: $targetDate, displayedComponents: [.date])
                            .datePickerStyle(.graphical)
                    }
                }
                
                if isEditing {
                    Section {
                        Button("Delete Goal", role: .destructive) {
                            showDeleteAlert = true
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Goal" : "New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .alert("Delete goal?", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if case .editGoal(let id) = sheet {
                        store.deleteGoal(id)
                    }
                    onDismiss()
                }
            } message: {
                Text("Stages, subgoals, and links for this goal will be removed.")
            }
            .onAppear {
                if !isEditing { titleFocused = true }
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        switch sheet {
        case .createGoal:
            let goal = Goal(
                title: trimmedTitle,
                description: description,
                status: status,
                targetDate: hasTargetDate ? targetDate : nil,
                stages: template?.stages ?? []
            )
            let id = store.addGoal(goal)
            onCreated(id)
        case .editGoal(let id):
            guard var goal = store.goal(id) else { break }
            goal.title = trimmedTitle
            goal.description = description
            goal.status = status
            goal.targetDate = hasTargetDate ? targetDate : nil
            store.updateGoal(goal)
        default:
            break
        }

        onDismiss()
    }
}

// MARK: - Stage editor

struct GoalStageEditorSheet: View {
    let sheet: GoalStrategySheet
    let store: GoalStrategyStore
    let onDismiss: () -> Void

    @State private var title: String
    @State private var summary: String
    @State private var status: GoalStageStatus
    @State private var hasTargetDate: Bool
    @State private var targetDate: Date
    @FocusState private var titleFocused: Bool

    init(sheet: GoalStrategySheet, store: GoalStrategyStore, onDismiss: @escaping () -> Void) {
        self.sheet = sheet
        self.store = store
        self.onDismiss = onDismiss

        var stage: GoalStage?
        if case .editStage(let goalID, let stageID) = sheet {
            stage = store.goal(goalID)?.stages.first { $0.id == stageID }
        }

        _title = State(initialValue: stage?.title ?? "")
        _summary = State(initialValue: stage?.summary ?? "")
        _status = State(initialValue: stage?.status ?? .planned)
        _hasTargetDate = State(initialValue: stage?.targetDate != nil)
        _targetDate = State(initialValue: stage?.targetDate ?? Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date())
    }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    
    private var isEditing: Bool {
        if case .editStage = sheet { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Stage Name", text: $title)
                        .focused($titleFocused)
                    TextField("Summary (optional)", text: $summary, axis: .vertical)
                        .lineLimit(2...5)
                }
                
                Section {
                    Picker("Status", selection: $status) {
                        ForEach(GoalStageStatus.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    
                    Toggle("Target Date", isOn: $hasTargetDate.animation())
                    
                    if hasTargetDate {
                        DatePicker("Target", selection: $targetDate, displayedComponents: [.date])
                            .datePickerStyle(.graphical)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Stage" : "New Stage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if !isEditing { titleFocused = true }
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        switch sheet {
        case .createStage(let goalID):
            _ = store.addStage(
                goalID: goalID,
                title: trimmedTitle,
                summary: summary,
                status: status,
                targetDate: hasTargetDate ? targetDate : nil
            )
        case .editStage(let goalID, let stageID):
            guard var stage = store.goal(goalID)?.stages.first(where: { $0.id == stageID }) else { break }
            stage.title = trimmedTitle
            stage.summary = summary
            stage.status = status
            stage.targetDate = hasTargetDate ? targetDate : nil
            store.updateStage(goalID: goalID, stage: stage)
        default:
            break
        }
        onDismiss()
    }
}

// MARK: - Subgoal editor

struct GoalSubgoalEditorSheet: View {
    let sheet: GoalStrategySheet
    let store: GoalStrategyStore
    let onDismiss: () -> Void

    @State private var title: String
    @State private var notes: String
    @State private var status: GoalSubgoalStatus
    @State private var hasTargetDate: Bool
    @State private var targetDate: Date
    @State private var manualProgress: Double
    @FocusState private var titleFocused: Bool

    init(sheet: GoalStrategySheet, store: GoalStrategyStore, onDismiss: @escaping () -> Void) {
        self.sheet = sheet
        self.store = store
        self.onDismiss = onDismiss

        var subgoal: GoalSubgoal?
        if case .editSubgoal(let goalID, let stageID, let subgoalID) = sheet {
            subgoal = store.goal(goalID)?
                .stages.first { $0.id == stageID }?
                .subgoals.first { $0.id == subgoalID }
        }

        _title = State(initialValue: subgoal?.title ?? "")
        _notes = State(initialValue: subgoal?.notes ?? "")
        _status = State(initialValue: subgoal?.status ?? .open)
        _hasTargetDate = State(initialValue: subgoal?.targetDate != nil)
        _targetDate = State(initialValue: subgoal?.targetDate ?? Calendar.current.date(byAdding: .weekOfYear, value: 2, to: Date()) ?? Date())
        _manualProgress = State(initialValue: subgoal?.manualProgress ?? 0)
    }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    
    private var isEditing: Bool {
        if case .editSubgoal = sheet { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Subgoal Name", text: $title)
                        .focused($titleFocused)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
                
                Section {
                    Picker("Status", selection: $status) {
                        ForEach(GoalSubgoalStatus.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Manual Progress")
                            Spacer()
                            Text("\(Int(manualProgress * 100))%")
                        }
                        Slider(value: $manualProgress, in: 0...1, step: 0.05)
                    }
                    
                    Toggle("Target Date", isOn: $hasTargetDate.animation())
                    
                    if hasTargetDate {
                        DatePicker("Target", selection: $targetDate, displayedComponents: [.date])
                            .datePickerStyle(.graphical)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Subgoal" : "New Subgoal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if !isEditing { titleFocused = true }
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        switch sheet {
        case .createSubgoal(let goalID, let stageID):
            _ = store.addSubgoal(
                goalID: goalID,
                stageID: stageID,
                title: trimmedTitle,
                notes: notes,
                status: status,
                targetDate: hasTargetDate ? targetDate : nil,
                manualProgress: manualProgress
            )
        case .editSubgoal(let goalID, let stageID, let subgoalID):
            guard var subgoal = store.goal(goalID)?
                .stages.first(where: { $0.id == stageID })?
                .subgoals.first(where: { $0.id == subgoalID })
            else { break }
            subgoal.title = trimmedTitle
            subgoal.notes = notes
            subgoal.status = status
            subgoal.targetDate = hasTargetDate ? targetDate : nil
            subgoal.manualProgress = manualProgress
            store.updateSubgoal(goalID: goalID, stageID: stageID, subgoal: subgoal)
        default:
            break
        }
        onDismiss()
    }
}

// MARK: - Work link picker

struct GoalWorkLinkPickerSheet: View {
    let goalID: UUID
    let stageID: UUID
    let subgoalID: UUID
    let store: GoalStrategyStore
    let tasksStore: TasksStore
    let onDismiss: () -> Void

    private var linkedKeys: Set<String> {
        guard let subgoal = store.goal(goalID)?
            .stages.first(where: { $0.id == stageID })?
            .subgoals.first(where: { $0.id == subgoalID })
        else { return [] }
        return Set(subgoal.linkedWork.map { key(kind: $0.targetKind, id: $0.targetID) })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        _ = store.createLinkedTask(goalID: goalID, stageID: stageID, subgoalID: subgoalID, tasksStore: tasksStore)
                        onDismiss()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("Create new linked task")
                        }
                    }
                }
                
                Section("Initiatives (\(tasksStore.fields.count))") {
                    ForEach(tasksStore.fields) { field in
                        linkRow(
                            kind: .field,
                            id: field.id,
                            title: field.name,
                            icon: field.resolvedIconSystemName,
                            tint: field.color
                        )
                    }
                }
                
                Section("Projects (\(tasksStore.projects.count))") {
                    ForEach(tasksStore.projects) { project in
                        linkRow(
                            kind: .project,
                            id: project.id,
                            title: project.name,
                            icon: project.resolvedIconSystemName,
                            tint: tasksStore.color(for: project)
                        )
                    }
                }
                
                Section("Open Tasks (\(tasksStore.activeTasks.count))") {
                    ForEach(tasksStore.activeTasks.prefix(60)) { task in
                        linkRow(
                            kind: .task,
                            id: task.id,
                            title: task.title,
                            icon: tasksStore.iconName(for: task),
                            tint: tasksStore.color(for: task)
                        )
                    }
                }
            }
            .navigationTitle("Link Work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func linkRow(kind: GoalWorkLink.TargetKind, id: UUID, title: String, icon: String, tint: Color) -> some View {
        let linked = linkedKeys.contains(key(kind: kind, id: id))
        return Button {
            if !linked {
                store.addWorkLink(
                    goalID: goalID,
                    stageID: stageID,
                    subgoalID: subgoalID,
                    link: GoalWorkLink(targetKind: kind, targetID: id, titleSnapshot: title)
                )
            }
        } label: {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 24)
                Text(title)
                    .foregroundStyle(CueInColors.textPrimary)
                Spacer()
                if linked {
                    Image(systemName: "checkmark")
                        .foregroundStyle(CueInColors.success)
                }
            }
        }
        .disabled(linked)
    }

    private func key(kind: GoalWorkLink.TargetKind, id: UUID) -> String {
        "\(kind.rawValue):\(id.uuidString)"
    }
}
