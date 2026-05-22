import SwiftUI

// MARK: - QuickCaptureSheet
/// Super-fast task entry. Autofocused title, inline chips below for
/// field / project / execution / priority / due-date. Save lands the task
/// directly into `TasksStore`; a "More…" shortcut opens the full editor
/// for the caller to handle if it wants to chain (not wired here).

struct QuickCaptureSheet: View {
    enum PresentationMode: Equatable {
        case full
        case compactComposer
    }

    let store: TasksStore
    let fields: [Field]
    let projects: [Project]
    var onDismiss: () -> Void
    var onExpand: (TaskItem) -> Void
    /// Fired after **Add task** commits the new row to ``TasksStore`` (before dismiss).
    var onSaved: ((TaskItem) -> Void)?
    /// When `false`, hides the sheet drag handle (e.g. when embedded in another nav stack).
    var showsDragHandle: Bool
    var presentationMode: PresentationMode
    private let fieldsByID: [UUID: Field]
    private let projectsByID: [UUID: Project]
    private let projectsByFieldID: [UUID: [Project]]

    @MainActor init(
        store: TasksStore,
        fields: [Field]? = nil,
        projects: [Project]? = nil,
        captureDefaultsToToday: Bool = true,
        onSaved: ((TaskItem) -> Void)? = nil,
        onDismiss: @escaping () -> Void,
        onExpand: @escaping (TaskItem) -> Void = { _ in },
        showsDragHandle: Bool = true,
        presentationMode: PresentationMode = .full
    ) {
        self.store = store
        let resolvedFields = fields ?? store.fields
        let resolvedProjects = projects ?? store.projects
        self.fields = resolvedFields
        self.projects = resolvedProjects
        self.fieldsByID = Dictionary(uniqueKeysWithValues: resolvedFields.map { ($0.id, $0) })
        self.projectsByID = Dictionary(uniqueKeysWithValues: resolvedProjects.map { ($0.id, $0) })
        self.projectsByFieldID = Dictionary(grouping: resolvedProjects, by: \.fieldID)
        self.onSaved = onSaved
        self.onDismiss = onDismiss
        self.onExpand = onExpand
        self.showsDragHandle = showsDragHandle
        self.presentationMode = presentationMode
        _fieldID = State(initialValue: resolvedFields.first?.id)
        _dueOption = State(initialValue: captureDefaultsToToday ? .today : .noDate)
    }

    /// Uses ``TasksStore/shared`` — separated so Swift 6 does not infer a nonisolated default-arg access to the actor-isolated singleton.
    @MainActor init(
        captureDefaultsToToday: Bool = true,
        onSaved: ((TaskItem) -> Void)? = nil,
        onDismiss: @escaping () -> Void,
        onExpand: @escaping (TaskItem) -> Void = { _ in },
        showsDragHandle: Bool = true,
        presentationMode: PresentationMode = .full
    ) {
        self.init(
            store: TasksStore.shared,
            captureDefaultsToToday: captureDefaultsToToday,
            onSaved: onSaved,
            onDismiss: onDismiss,
            onExpand: onExpand,
            showsDragHandle: showsDragHandle,
            presentationMode: presentationMode
        )
    }

    @State private var title: String = ""
    @State private var fieldID: UUID? = nil
    @State private var projectID: UUID? = nil
    @State private var executionType: TaskExecutionType? = nil
    @State private var priority: TaskPriority = .normal
    @State private var status: TaskStatus = .scheduled
    @State private var dueOption: DueOption
    @State private var notes: String = ""
    @State private var subtasks: [TaskSubtask] = []
    @State private var newSubtaskTitle = ""
    @State private var saveHaptic = false
    @State private var selectHaptic = false
    @State private var didRequestInitialFocus = false

    @FocusState private var titleFocused: Bool
    @FocusState private var notesFocused: Bool
    @FocusState private var subtaskFocused: Bool

    enum DueOption: Hashable {
        case today, tomorrow, noDate
        var label: String {
            switch self {
            case .today:    return "Today"
            case .tomorrow: return "Tomorrow"
            case .noDate:   return "Inbox"
            }
        }
        var icon: String {
            switch self {
            case .today:    return "sun.max.fill"
            case .tomorrow: return "arrow.turn.up.right"
            case .noDate:   return "tray.fill"
            }
        }
        var date: Date? {
            switch self {
            case .today:    return Calendar.current.startOfDay(for: Date())
            case .tomorrow: return Calendar.current.date(byAdding: .day, value: 1,
                                                         to: Calendar.current.startOfDay(for: Date()))
            case .noDate:   return nil
            }
        }
    }

    // MARK: Body

    var body: some View {
        content
        .background(CueInColors.surfacePrimary)
        .sensoryFeedback(.success, trigger: saveHaptic)
        .sensoryFeedback(.selection, trigger: selectHaptic)
        .onAppear(perform: focusTitleOnce)
    }

    private var content: some View {
        VStack(spacing: 0) {
            if showsDragHandle {
                handle
            }
            titleField
                .padding(.horizontal, CueInSpacing.base)
                .padding(.top, presentationMode == .full ? CueInSpacing.md : CueInSpacing.sm)

            chips
                .padding(.top, CueInSpacing.md)

            if presentationMode == .full {
                liteEditorContent
                    .padding(.horizontal, CueInSpacing.base)
                    .padding(.top, CueInSpacing.xl)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))

                if showsExpandedSaveButton {
                    expandedSaveButton
                        .padding(.horizontal, CueInSpacing.base)
                        .padding(.top, CueInSpacing.lg)
                        .padding(.bottom, CueInSpacing.md)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .padding(.bottom, presentationMode == .compactComposer ? CueInSpacing.md : 0)
        .animation(.easeInOut(duration: 0.18), value: showsExpandedSaveButton)
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: presentationMode)
    }

    // MARK: Handle + title

    private var handle: some View {
        Capsule()
            .fill(CueInColors.textTertiary.opacity(0.4))
            .frame(width: 36, height: 4)
            .padding(.top, CueInSpacing.sm)
    }

    private var titleField: some View {
        HStack(spacing: CueInSpacing.md) {
            Menu {
                ForEach(TaskStatus.statusPickerOrdering) { option in
                    Button {
                        setStatus(option)
                        selectHaptic.toggle()
                    } label: {
                        Label(option.label, systemImage: option.icon)
                    }
                }
            } label: {
                Image(systemName: status.icon)
                    .font(.system(size: 24, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(status.color)
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel("Task status")

            TextField("What needs doing?", text: $title)
                .font(presentationMode == .full ? CueInTypography.title : Font.system(size: 26, weight: .semibold, design: .default))
                .foregroundStyle(CueInColors.textPrimary)
                .tint(CueInColors.accentFocus)
                .focused($titleFocused)
                .submitLabel(.done)
                .onSubmit { save() }
                .lineLimit(1)
        }
    }

    // MARK: Chips row

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CueInSpacing.sm) {
                moreChip

                // Initiative
                Menu {
                    ForEach(fields) { f in
                        Button {
                            if fieldID != f.id { projectID = nil }
                            fieldID = f.id
                            selectHaptic.toggle()
                        } label: { Label(f.name, systemImage: f.resolvedIconSystemName) }
                    }
                } label: {
                    chipLabel(
                        icon: selectedField?.resolvedIconSystemName ?? "square.grid.2x2",
                        text: selectedField?.name ?? "Initiative",
                        accent: selectedField?.color
                    )
                }

                // Project
                Menu {
                    Button { projectID = nil; selectHaptic.toggle() } label: {
                        Label("No project", systemImage: "xmark")
                    }
                    ForEach(projectOptions) { p in
                        Button {
                            projectID = p.id
                            if fieldID == nil { fieldID = p.fieldID }
                            selectHaptic.toggle()
                        } label: { Label(p.name, systemImage: p.resolvedIconSystemName) }
                    }
                } label: {
                    chipLabel(
                        icon: selectedProject?.resolvedIconSystemName ?? "folder",
                        text: selectedProject?.name ?? "Project",
                        accent: selectedProject.map(projectColor)
                    )
                }

                // Execution type — inline segmented
                executionSegmented

                // Priority
                Menu {
                    ForEach(TaskPriority.allCases) { p in
                        Button { priority = p; selectHaptic.toggle() } label: {
                            Label(p.label, systemImage: p.icon)
                        }
                    }
                } label: {
                    chipLabel(
                        icon: priority.icon,
                        text: priority.label,
                        accent: priority.color
                    )
                }

                // Due
                Menu {
                    Button {
                        setDueOption(.today)
                        selectHaptic.toggle()
                    } label: { Label("Today", systemImage: "sun.max") }
                    Button {
                        setDueOption(.tomorrow)
                        selectHaptic.toggle()
                    } label: { Label("Tomorrow", systemImage: "arrow.turn.up.right") }
                    Button {
                        setDueOption(.noDate)
                        selectHaptic.toggle()
                    } label: { Label("Inbox", systemImage: "tray") }
                } label: {
                    chipLabel(
                        icon: dueOption.icon,
                        text: dueOption.label,
                        accent: dueOption == .today ? CueInColors.accentFixed : nil
                    )
                }
            }
            .padding(.horizontal, CueInSpacing.base)
        }
    }

    private var moreChip: some View {
        Button {
            onExpand(buildEditorDraft())
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CueInColors.textSecondary)
                .frame(width: 34, height: 34)
                .background(CueInColors.surfaceSecondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(CueInColors.divider, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More task options")
    }

    private var selectedField: Field? {
        guard let fieldID else { return nil }
        return fieldsByID[fieldID]
    }

    private var selectedProject: Project? {
        guard let projectID else { return nil }
        return projectsByID[projectID]
    }

    private var projectOptions: [Project] {
        guard let fieldID else { return projects }
        return projectsByFieldID[fieldID] ?? []
    }

    private func projectColor(_ project: Project) -> Color {
        if let hex = project.colorHexOverride {
            return Color(hex: hex)
        }
        return fieldsByID[project.fieldID]?.color ?? CueInColors.textTertiary
    }

    private var executionSegmented: some View {
        HStack(spacing: 0) {
            Button {
                executionType = nil
                selectHaptic.toggle()
            } label: {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(executionType == nil ? CueInColors.textPrimary : CueInColors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(executionType == nil ? CueInColors.surfacePrimary.opacity(0.7) : Color.clear)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            ForEach(TaskExecutionType.allCases) { type in
                let on = executionType == type
                Button {
                    executionType = type
                    selectHaptic.toggle()
                } label: {
                    Image(systemName: type.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(on ? CueInColors.textPrimary : CueInColors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(on ? CueInColors.surfacePrimary.opacity(0.7) : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .background(CueInColors.surfaceSecondary)
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(CueInColors.divider, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func chipLabel(icon: String, text: String, accent: Color?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent ?? CueInColors.textSecondary)
            Text(text)
                .font(CueInTypography.captionMedium)
                .foregroundStyle(accent == nil ? CueInColors.textSecondary : CueInColors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, CueInSpacing.md)
        .padding(.vertical, 8)
        .background(
            accent.map { $0.opacity(0.12) } ?? CueInColors.surfaceSecondary
        )
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(
                accent?.opacity(0.3) ?? CueInColors.divider,
                lineWidth: 0.5
            )
        )
    }

    // MARK: Save

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var hasNotes: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasSubtasks: Bool {
        subtasks.contains { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var showsExpandedSaveButton: Bool {
        canSave && (hasNotes || hasSubtasks)
    }

    private var canAddSubtask: Bool {
        !newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var liteEditorContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Add description...", text: $notes, axis: .vertical)
                .font(Font.system(size: 18, weight: .regular))
                .foregroundStyle(CueInColors.textSecondary)
                .tint(CueInColors.accentFocus)
                .focused($notesFocused)
                .lineLimit(1...8)
                .padding(.bottom, CueInSpacing.md)

            Divider()
                .background(CueInColors.divider)

            if !subtasks.isEmpty {
                subtaskRows
                Divider()
                    .background(CueInColors.divider)
                    .padding(.leading, 44)
            }

            addSubtaskRow
        }
    }

    private var subtaskRows: some View {
        VStack(spacing: 0) {
            ForEach(subtasks.indices, id: \.self) { index in
                subtaskRow(index: index)
                if index < subtasks.indices.last ?? 0 {
                    Divider()
                        .background(CueInColors.divider)
                        .padding(.leading, 44)
                }
            }
        }
    }

    private func subtaskRow(index: Int) -> some View {
        HStack(spacing: CueInSpacing.sm) {
            Button {
                subtasks[index].isCompleted.toggle()
            } label: {
                Image(systemName: subtasks[index].isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(subtasks[index].isCompleted ? CueInColors.success : CueInColors.textTertiary)
            }
            .buttonStyle(.plain)

            TextField("Sub-task", text: Binding(
                get: { subtasks[index].title },
                set: { subtasks[index].title = $0 }
            ))
            .font(CueInTypography.body)
            .foregroundStyle(subtasks[index].isCompleted ? CueInColors.textTertiary : CueInColors.textPrimary)
            .strikethrough(subtasks[index].isCompleted, color: CueInColors.textTertiary)

            Button {
                subtasks.remove(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CueInColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, CueInSpacing.md)
        .padding(.vertical, 11)
    }

    private var addSubtaskRow: some View {
        HStack(spacing: CueInSpacing.sm) {
            Image(systemName: "plus.circle")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(CueInColors.textTertiary)

            TextField("Add sub-task", text: $newSubtaskTitle)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textPrimary)
                .tint(CueInColors.accentFocus)
                .focused($subtaskFocused)
                .submitLabel(.done)
                .onSubmit(addSubtask)

            Button(action: addSubtask) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
            }
            .disabled(!canAddSubtask)
            .foregroundStyle(canAddSubtask ? CueInColors.accentFocus : CueInColors.textTertiary)
        }
        .padding(.horizontal, CueInSpacing.md)
        .frame(height: 48)
    }

    private var expandedSaveButton: some View {
        HStack {
            Spacer(minLength: 0)
            Button(action: save) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Add task")
                        .font(CueInTypography.bodyMedium)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(CueInColors.accentFocus)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!showsExpandedSaveButton)
        }
    }

    private func buildDraft() -> TaskItem? {
        guard canSave else { return nil }
        return buildEditorDraft()
    }

    private func buildEditorDraft() -> TaskItem {
        let scheduledDate = scheduledDateForCurrentStatus
        return TaskItem(
            title: title.trimmingCharacters(in: .whitespaces),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            fieldID: fieldID,
            projectID: projectID,
            executionType: executionType,
            priority: priority,
            scheduledDate: scheduledDate,
            status: status,
            subtasks: normalizedSubtasks
        )
    }

    private func save() {
        guard let draft = buildDraft() else { return }
        store.addTask(draft)
        onSaved?(draft)
        saveHaptic.toggle()
        onDismiss()
    }

    private var normalizedSubtasks: [TaskSubtask] {
        subtasks
            .map { subtask in
                TaskSubtask(
                    id: subtask.id,
                    title: subtask.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    isCompleted: subtask.isCompleted,
                    createdAt: subtask.createdAt
                )
            }
            .filter { !$0.title.isEmpty }
    }

    private func addSubtask() {
        let clean = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        subtasks.append(TaskSubtask(title: clean))
        newSubtaskTitle = ""
        selectHaptic.toggle()
    }

    private var scheduledDateForCurrentStatus: Date? {
        switch status {
        case .inbox, .archived:
            return nil
        case .scheduled, .active, .paused, .completed:
            return dueOption.date ?? Calendar.current.startOfDay(for: Date())
        }
    }

    private func setStatus(_ newStatus: TaskStatus) {
        status = newStatus
        switch newStatus {
        case .inbox, .archived:
            dueOption = .noDate
        case .scheduled, .active, .paused, .completed:
            if dueOption == .noDate {
                dueOption = .today
            }
        }
    }

    private func setDueOption(_ option: DueOption) {
        dueOption = option
        switch option {
        case .noDate:
            if status == .scheduled {
                status = .inbox
            }
        case .today, .tomorrow:
            if status == .inbox || status == .archived {
                status = .scheduled
            }
        }
    }

    private func focusTitleOnce() {
        guard !didRequestInitialFocus else { return }
        didRequestInitialFocus = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            titleFocused = true
        }
    }
}
