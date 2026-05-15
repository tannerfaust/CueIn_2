import SwiftUI

// MARK: - Goal editor

struct GoalEditorSheet: View {
    let sheet: GoalStrategySheet
    let store: GoalStrategyStore
    let onCreated: (UUID) -> Void
    let onDismiss: () -> Void

    @State private var title: String
    @State private var why: String
    @State private var successMetric: String
    @State private var notes: String
    @State private var iconName: String
    @State private var colorHex: UInt
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
            selectedTemplate = GoalTemplate.library.first { $0.id == templateID }
        default:
            break
        }

        template = selectedTemplate

        _title = State(initialValue: existing?.title ?? selectedTemplate?.title ?? "")
        _why = State(initialValue: existing?.why ?? selectedTemplate?.why ?? "")
        _successMetric = State(initialValue: existing?.successMetric ?? "")
        _notes = State(initialValue: existing?.notes ?? "")
        _iconName = State(initialValue: existing?.iconName ?? selectedTemplate?.iconName ?? "target")
        _colorHex = State(initialValue: existing?.colorHex ?? selectedTemplate?.colorHex ?? 0x34C759)
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

    private var accent: Color { Color(hex: colorHex) }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: CueInSpacing.lg) {
                    previewHeader
                    nameSection
                    canvasStarterSection
                    appearanceSection
                    statusSection
                    if isEditing { deleteSection }
                }
                .padding(.top, CueInSpacing.base)
                .padding(.bottom, CueInSpacing.huge)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(CueInColors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }
                        .foregroundStyle(CueInColors.textSecondary)
                }
                ToolbarItem(placement: .principal) {
                    Text(isEditing ? "Edit Goal" : "New Goal")
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? CueInColors.accentFocus : CueInColors.textTertiary)
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
                Text("Stages, subgoals, links, canvas notes, and reviews for this goal will be removed.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var previewHeader: some View {
        VStack(spacing: CueInSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(accent.opacity(0.16))
                    .frame(width: 68, height: 68)
                Image(systemName: iconName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(accent)
            }

            Text(title.isEmpty ? "Grand goal" : title)
                .font(CueInTypography.title)
                .foregroundStyle(title.isEmpty ? CueInColors.textTertiary : CueInColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, CueInSpacing.screenHorizontal)

            if let template {
                Text(template.subtitle)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CueInSpacing.lg)
    }

    private var nameSection: some View {
        SheetSection("Direction") {
            TextField("e.g. Ship CueIn v1", text: $title, axis: .vertical)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textPrimary)
                .tint(accent)
                .focused($titleFocused)
                .padding(.horizontal, CueInSpacing.base)
                .padding(.vertical, 12)

            SheetRowDivider()

            TextField("Why this matters", text: $why, axis: .vertical)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textPrimary)
                .tint(accent)
                .padding(.horizontal, CueInSpacing.base)
                .padding(.vertical, 12)

            SheetRowDivider()

            TextField("Success metric (optional)", text: $successMetric, axis: .vertical)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textPrimary)
                .tint(accent)
                .padding(.horizontal, CueInSpacing.base)
                .padding(.vertical, 12)
        }
    }

    private var canvasStarterSection: some View {
        SheetSection("Notes") {
            TextField("Extra context (optional)", text: $notes, axis: .vertical)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textPrimary)
                .tint(accent)
                .lineLimit(3...6)
                .padding(.horizontal, CueInSpacing.base)
                .padding(.vertical, 12)
        }
    }

    private var appearanceSection: some View {
        SheetSection("Look") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ForEach(GoalIconPalette.icons, id: \.self) { icon in
                    Button {
                        iconName = icon
                    } label: {
                        iconCell(icon: icon, selected: icon == iconName)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(CueInSpacing.md)

            SheetRowDivider()

            HStack(spacing: CueInSpacing.sm) {
                ForEach(GoalIconPalette.colors, id: \.self) { hex in
                    Button {
                        colorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle()
                                    .strokeBorder(hex == colorHex ? Color.white.opacity(0.8) : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(CueInSpacing.md)
        }
    }

    private var statusSection: some View {
        SheetSection("Plan") {
            PickerRow(icon: status.icon, label: "Status", iconColor: status.tint) {
                Menu {
                    ForEach(GoalStatus.allCases) { item in
                        Button { status = item } label: {
                            Label(item.label, systemImage: item.icon)
                        }
                    }
                } label: {
                    menuValue(status.label)
                }
            }

            SheetRowDivider()

            Toggle(isOn: $hasTargetDate.animation(.easeInOut(duration: 0.18))) {
                HStack(spacing: CueInSpacing.md) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CueInColors.textSecondary)
                        .frame(width: 18)
                    Text("Target date")
                        .font(CueInTypography.body)
                        .foregroundStyle(CueInColors.textSecondary)
                }
            }
            .tint(accent)
            .padding(.horizontal, CueInSpacing.base)
            .padding(.vertical, 10)

            if hasTargetDate {
                SheetRowDivider()
                DatePicker("Target", selection: $targetDate, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .tint(accent)
                    .padding(.horizontal, CueInSpacing.base)
                    .padding(.bottom, CueInSpacing.sm)
            }
        }
    }

    private var deleteSection: some View {
        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            HStack {
                Spacer()
                Image(systemName: "trash")
                Text("Delete goal")
                    .fontWeight(.medium)
                Spacer()
            }
            .foregroundStyle(CueInColors.danger)
            .padding(.vertical, CueInSpacing.md)
            .background(CueInColors.danger.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
            .padding(.horizontal, CueInSpacing.screenHorizontal)
        }
        .buttonStyle(.plain)
    }

    private func iconCell(icon: String, selected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? accent.opacity(0.18) : CueInColors.surfaceSecondary)
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selected ? accent : CueInColors.textSecondary)
        }
        .frame(height: 44)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? accent.opacity(0.42) : Color.clear, lineWidth: 1)
        )
    }

    private func menuValue(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textPrimary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CueInColors.textTertiary)
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        switch sheet {
        case .createGoal:
            let goal = Goal(
                title: trimmedTitle,
                why: why,
                successMetric: successMetric,
                notes: notes,
                iconName: iconName,
                colorHex: colorHex,
                status: status,
                targetDate: hasTargetDate ? targetDate : nil,
                stages: template?.stages ?? [],
                canvas: template?.canvas ?? GoalCanvas()
            )
            let id = store.addGoal(goal)
            onCreated(id)
        case .editGoal(let id):
            guard var goal = store.goal(id) else { break }
            goal.title = trimmedTitle
            goal.why = why
            goal.successMetric = successMetric
            goal.notes = notes
            goal.iconName = iconName
            goal.colorHex = colorHex
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

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: CueInSpacing.lg) {
                    SheetSection("Stage") {
                        TextField("e.g. Foundation", text: $title)
                            .font(CueInTypography.body)
                            .foregroundStyle(CueInColors.textPrimary)
                            .tint(CueInColors.accentFocus)
                            .padding(.horizontal, CueInSpacing.base)
                            .padding(.vertical, 12)

                        SheetRowDivider()

                        TextField("Short strategy for this stage", text: $summary, axis: .vertical)
                            .font(CueInTypography.body)
                            .foregroundStyle(CueInColors.textPrimary)
                            .tint(CueInColors.accentFocus)
                            .lineLimit(2...5)
                            .padding(.horizontal, CueInSpacing.base)
                            .padding(.vertical, 12)
                    }

                    SheetSection("Plan") {
                        PickerRow(icon: status.icon, label: "Status", iconColor: status.tint) {
                            Menu {
                                ForEach(GoalStageStatus.allCases) { item in
                                    Button { status = item } label: { Label(item.label, systemImage: item.icon) }
                                }
                            } label: {
                                menuValue(status.label)
                            }
                        }

                        SheetRowDivider()

                        Toggle("Target date", isOn: $hasTargetDate)
                            .font(CueInTypography.body)
                            .foregroundStyle(CueInColors.textSecondary)
                            .tint(CueInColors.accentFocus)
                            .padding(.horizontal, CueInSpacing.base)
                            .padding(.vertical, 10)

                        if hasTargetDate {
                            SheetRowDivider()
                            DatePicker("Target", selection: $targetDate, displayedComponents: [.date])
                                .datePickerStyle(.graphical)
                                .tint(CueInColors.accentFocus)
                                .padding(.horizontal, CueInSpacing.base)
                        }
                    }
                }
                .padding(.top, CueInSpacing.base)
                .padding(.bottom, CueInSpacing.huge)
            }
            .background(CueInColors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }
                        .foregroundStyle(CueInColors.textSecondary)
                }
                ToolbarItem(placement: .principal) {
                    Text(isEditing ? "Edit Stage" : "New Stage")
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? CueInColors.accentFocus : CueInColors.textTertiary)
                        .disabled(!canSave)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var isEditing: Bool {
        if case .editStage = sheet { return true }
        return false
    }

    private func menuValue(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textPrimary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CueInColors.textTertiary)
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

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: CueInSpacing.lg) {
                    SheetSection("Subgoal") {
                        TextField("e.g. Publish beta build", text: $title, axis: .vertical)
                            .font(CueInTypography.body)
                            .foregroundStyle(CueInColors.textPrimary)
                            .tint(CueInColors.accentFocus)
                            .padding(.horizontal, CueInSpacing.base)
                            .padding(.vertical, 12)

                        SheetRowDivider()

                        TextField("Notes or acceptance criteria", text: $notes, axis: .vertical)
                            .font(CueInTypography.body)
                            .foregroundStyle(CueInColors.textPrimary)
                            .tint(CueInColors.accentFocus)
                            .lineLimit(2...5)
                            .padding(.horizontal, CueInSpacing.base)
                            .padding(.vertical, 12)
                    }

                    SheetSection("Progress") {
                        PickerRow(icon: status.icon, label: "Status", iconColor: status.tint) {
                            Menu {
                                ForEach(GoalSubgoalStatus.allCases) { item in
                                    Button { status = item } label: { Label(item.label, systemImage: item.icon) }
                                }
                            } label: {
                                menuValue(status.label)
                            }
                        }

                        SheetRowDivider()

                        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                            HStack {
                                Text("Manual progress")
                                    .font(CueInTypography.body)
                                    .foregroundStyle(CueInColors.textSecondary)
                                Spacer()
                                Text("\(Int(manualProgress * 100))%")
                                    .font(CueInTypography.captionMedium)
                                    .foregroundStyle(CueInColors.textPrimary)
                                    .monospacedDigit()
                            }
                            Slider(value: $manualProgress, in: 0...1, step: 0.05)
                                .tint(CueInColors.accentFocus)
                        }
                        .padding(.horizontal, CueInSpacing.base)
                        .padding(.vertical, 12)

                        SheetRowDivider()

                        Toggle("Target date", isOn: $hasTargetDate)
                            .font(CueInTypography.body)
                            .foregroundStyle(CueInColors.textSecondary)
                            .tint(CueInColors.accentFocus)
                            .padding(.horizontal, CueInSpacing.base)
                            .padding(.vertical, 10)

                        if hasTargetDate {
                            SheetRowDivider()
                            DatePicker("Target", selection: $targetDate, displayedComponents: [.date])
                                .datePickerStyle(.graphical)
                                .tint(CueInColors.accentFocus)
                                .padding(.horizontal, CueInSpacing.base)
                        }
                    }
                }
                .padding(.top, CueInSpacing.base)
                .padding(.bottom, CueInSpacing.huge)
            }
            .background(CueInColors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }
                        .foregroundStyle(CueInColors.textSecondary)
                }
                ToolbarItem(placement: .principal) {
                    Text(isEditing ? "Edit Subgoal" : "New Subgoal")
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? CueInColors.accentFocus : CueInColors.textTertiary)
                        .disabled(!canSave)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var isEditing: Bool {
        if case .editSubgoal = sheet { return true }
        return false
    }

    private func menuValue(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textPrimary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CueInColors.textTertiary)
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
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: CueInSpacing.xl) {
                    quickActionSection
                    workSection(title: "Initiatives", caption: "\(tasksStore.fields.count)") {
                        ForEach(tasksStore.fields) { field in
                            linkRow(
                                kind: .field,
                                id: field.id,
                                title: field.name,
                                subtitle: field.summary.isEmpty ? "Initiative" : field.summary,
                                icon: field.resolvedIconSystemName,
                                tint: field.color
                            )
                        }
                    }
                    workSection(title: "Projects", caption: "\(tasksStore.projects.count)") {
                        ForEach(tasksStore.projects) { project in
                            linkRow(
                                kind: .project,
                                id: project.id,
                                title: project.name,
                                subtitle: tasksStore.field(project.fieldID)?.name ?? "Project",
                                icon: project.resolvedIconSystemName,
                                tint: tasksStore.color(for: project)
                            )
                        }
                    }
                    workSection(title: "Open tasks", caption: "\(tasksStore.activeTasks.count)") {
                        ForEach(tasksStore.activeTasks.prefix(60)) { task in
                            linkRow(
                                kind: .task,
                                id: task.id,
                                title: task.title,
                                subtitle: task.projectID.flatMap { tasksStore.project($0)?.name } ?? task.fieldID.flatMap { tasksStore.field($0)?.name } ?? "Task",
                                icon: tasksStore.iconName(for: task),
                                tint: tasksStore.color(for: task)
                            )
                        }
                    }
                }
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.top, CueInSpacing.base)
                .padding(.bottom, CueInLayout.scrollBottomInset)
            }
            .background(CueInColors.background.ignoresSafeArea())
            .navigationTitle("Link Work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(CueInColors.accentFocus)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var quickActionSection: some View {
        CueInCard(padding: CueInSpacing.md) {
            VStack(alignment: .leading, spacing: CueInSpacing.md) {
                Text("Turn this subgoal into work")
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                Text("Create an inbox task from the subgoal, or link existing initiatives, projects, and tasks below.")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    _ = store.createLinkedTask(goalID: goalID, stageID: stageID, subgoalID: subgoalID, tasksStore: tasksStore)
                } label: {
                    HStack {
                        Image(systemName: "checklist")
                        Text("Create linked task")
                        Spacer()
                        Image(systemName: "plus")
                    }
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, CueInSpacing.md)
                    .background(CueInColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: CueInSpacing.chipRadius, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func workSection<Content: View>(title: String, caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            GoalLinkSectionHeading(title: title, caption: caption)
            VStack(spacing: CueInSpacing.sm) {
                content()
            }
        }
    }

    private func linkRow(kind: GoalWorkLink.TargetKind, id: UUID, title: String, subtitle: String, icon: String, tint: Color) -> some View {
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
            CueInCard(padding: CueInSpacing.md) {
                HStack(spacing: CueInSpacing.md) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 34, height: 34)
                        .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: CueInSpacing.chipRadius, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(CueInTypography.captionMedium)
                            .foregroundStyle(CueInColors.textPrimary)
                            .lineLimit(2)
                        Text(subtitle)
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: linked ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(linked ? CueInColors.success : CueInColors.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(linked)
    }

    private func key(kind: GoalWorkLink.TargetKind, id: UUID) -> String {
        "\(kind.rawValue):\(id.uuidString)"
    }
}

// MARK: - Review entry

struct GoalReviewEntrySheet: View {
    let goalID: UUID
    let store: GoalStrategyStore
    let onDismiss: () -> Void

    @State private var moved = ""
    @State private var stalled = ""
    @State private var changed = ""
    @State private var next = ""

    private var canSave: Bool {
        [moved, stalled, changed, next].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: CueInSpacing.lg) {
                    reviewField(title: "What moved?", text: $moved, icon: "arrow.up.right.circle.fill")
                    reviewField(title: "What stalled?", text: $stalled, icon: "exclamationmark.triangle.fill")
                    reviewField(title: "What changed?", text: $changed, icon: "arrow.triangle.2.circlepath")
                    reviewField(title: "What is next?", text: $next, icon: "bolt.fill")
                }
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.top, CueInSpacing.base)
                .padding(.bottom, CueInLayout.scrollBottomInset)
            }
            .background(CueInColors.background.ignoresSafeArea())
            .navigationTitle("Strategy Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }
                        .foregroundStyle(CueInColors.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? CueInColors.accentFocus : CueInColors.textTertiary)
                        .disabled(!canSave)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func reviewField(title: String, text: Binding<String>, icon: String) -> some View {
        CueInCard(padding: CueInSpacing.md) {
            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                HStack(spacing: CueInSpacing.sm) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CueInColors.accentFocus)
                    Text(title)
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                }

                TextEditor(text: text)
                    .font(CueInTypography.body)
                    .foregroundStyle(CueInColors.textPrimary)
                    .tint(CueInColors.accentFocus)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96)
                    .padding(CueInSpacing.sm)
                    .background(CueInColors.surfaceSecondary.opacity(0.55), in: RoundedRectangle(cornerRadius: CueInSpacing.chipRadius, style: .continuous))
            }
        }
    }

    private func save() {
        store.addReviewEntry(
            goalID: goalID,
            entry: GoalReviewEntry(moved: moved, stalled: stalled, changed: changed, next: next)
        )
        onDismiss()
    }
}

// MARK: - Palettes and local helpers

private enum GoalIconPalette {
    static let icons = [
        "target",
        "scope",
        "flag.fill",
        "paperplane.fill",
        "sparkles",
        "flame.fill",
        "heart.fill",
        "figure.run",
        "book.fill",
        "graduationcap.fill",
        "briefcase.fill",
        "chart.line.uptrend.xyaxis",
        "hammer.fill",
        "lightbulb.fill",
        "leaf.fill",
        "moon.stars.fill",
        "dollarsign.circle.fill",
        "person.2.fill"
    ]

    static let colors: [UInt] = [
        0x34C759,
        0x5BC6B9,
        0xE2B253,
        0xA99BE0,
        0x79B6E8,
        0xE98989
    ]
}

private struct GoalLinkSectionHeading: View {
    let title: String
    let caption: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(CueInTypography.title)
                .foregroundStyle(CueInColors.textPrimary)
            Spacer()
            Text(caption)
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)
                .monospacedDigit()
        }
    }
}

#Preview {
    GoalEditorSheet(
        sheet: .createGoal(templateID: nil),
        store: .shared,
        onCreated: { _ in },
        onDismiss: { }
    )
    .preferredColorScheme(.dark)
}
