import SwiftUI

// MARK: - TaskDetailSheet
/// Unified editor for creating and editing `TaskItem` rows.
/// The surface is intentionally issue-editor-first: title, description, compact
/// properties, tags, and subtasks stay visible before advanced planning controls.

struct TaskDetailSheet: View {

    enum Mode {
        case edit(UUID)
        case create
    }

    let mode: Mode
    var store: TasksStore
    var onDismiss: () -> Void
    var configureCreateDraft: ((inout TaskItem) -> Void)?
    var onCreated: ((TaskItem) -> Void)?

    @State private var draft: TaskItem
    @State private var showingDelete = false
    @State private var newTagText = ""
    @State private var newSubtaskTitle = ""
    @State private var accessoryPanel: TaskEditorAccessoryPanel? = nil
    @State private var isStatusPopoverPresented = false
    @State private var didRequestInitialFocus = false
    @FocusState private var titleFocused: Bool
    @FocusState private var descriptionFocused: Bool

    init(
        mode: Mode,
        store: TasksStore,
        configureCreateDraft: ((inout TaskItem) -> Void)? = nil,
        onCreated: ((TaskItem) -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.mode = mode
        self.store = store
        self.configureCreateDraft = configureCreateDraft
        self.onCreated = onCreated
        self.onDismiss = onDismiss
        switch mode {
        case .edit(let id):
            let existing = store.tasks.first { $0.id == id }
            _draft = State(initialValue: existing ?? TaskItem(title: ""))
        case .create:
            var initialDraft = TaskItem(title: "")
            configureCreateDraft?(&initialDraft)
            _draft = State(initialValue: initialDraft)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CueInColors.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: CueInSpacing.md) {
                        topProperties
                        if isNotionLocked {
                            notionLockedBanner
                        }
                        titleAndDescription
                        inlineDetails
                    }
                    .padding(.horizontal, CueInSpacing.screenHorizontal)
                    .padding(.top, CueInSpacing.sm)
                    .padding(.bottom, editorContentBottomPadding)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                editorAccessory
            }
            .navigationTitle("Task")
            .cueInNavigationBarTitleDisplayMode(.inline)
            .cueInNavigationToolbarColorScheme()
            .toolbar {
                CueInEditorToolbar(
                    saveEnabled: canSave,
                    onClose: onDismiss,
                    onSave: save
                ) {
                    projectHeaderChip
                }
            }
            .alert(deleteAlertTitle, isPresented: $showingDelete) {
                Button("Cancel", role: .cancel) { }
                Button(deleteAlertActionTitle, role: .destructive) {
                    store.deleteTask(draft.id)
                    onDismiss()
                }
            } message: {
                Text(deleteAlertMessage)
            }
        }
        .cueInPreferredColorScheme()
        .onAppear(perform: focusTitleOnce)
    }
}

private enum TaskEditorAccessoryPanel {
    case dates
    case tags
    case subtasks
}

// MARK: - Main Layout

private extension TaskDetailSheet {
    var projectHeaderChip: some View {
        Group {
            if isNotionLocked {
                CueInEditorPrincipalChip(
                    icon: "lock.fill",
                    title: "Notion",
                    tint: CueInColors.textPrimary
                )
            } else {
                Menu {
                    Section("Initiative") {
                        fieldMenuContent
                    }

                    Section("Project") {
                        projectMenuContent
                    }
                } label: {
                    CueInEditorPrincipalChip(
                        icon: organizationIcon,
                        title: organizationTitle,
                        tint: organizationTint
                    )
                }
            }
        }
    }

    var titleAndDescription: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isNotionLocked {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CueInColors.textTertiary)
                            .padding(.top, 9)

                        Text(draft.title)
                            .font(Font.system(size: 30, weight: .bold))
                            .foregroundStyle(CueInColors.textPrimary)
                            .lineLimit(1...4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(draft.notes.isEmpty ? "No Notion description." : draft.notes)
                        .font(Font.system(size: 18, weight: .regular))
                        .foregroundStyle(draft.notes.isEmpty ? CueInColors.textTertiary : CueInColors.textSecondary)
                        .lineLimit(8...22)
                        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
                }
            } else {
                TextField("Task title", text: $draft.title, axis: .vertical)
                    .font(Font.system(size: 30, weight: .bold))
                    .foregroundStyle(CueInColors.textPrimary)
                    .tint(CueInColors.accentFocus)
                    .focused($titleFocused)
                    .lineLimit(1...3)

                TextField("Add description...", text: $draft.notes, axis: .vertical)
                    .font(Font.system(size: 18, weight: .regular))
                    .foregroundStyle(CueInColors.textSecondary)
                    .tint(CueInColors.accentFocus)
                    .focused($descriptionFocused)
                    .lineLimit(8...22)
                    /// Slightly shorter than before so sub-tasks sit a bit closer under the notes.
                    .frame(minHeight: 260, alignment: .topLeading)
            }
        }
        .padding(.top, 18)
    }

    var notionLockedBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("N")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(CueInColors.textPrimary)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("This task is from Notion")
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                Text("CueIn keeps the content read-only here. You can change status or archive the CueIn copy.")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CueInColors.surfacePrimary.opacity(0.64), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(CueInColors.divider.opacity(0.55), lineWidth: 0.8)
        )
    }

    var topProperties: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                statusChip
                if !isNotionLocked {
                    priorityChip
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    var editorContentBottomPadding: CGFloat {
        switch accessoryPanel {
        case .dates:
            return 306
        case .tags, .subtasks:
            return 218
        case nil:
            return 148
        }
    }

    @ViewBuilder
    var inlineDetails: some View {
        if !draft.tags.isEmpty || !draft.subtasks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !draft.subtasks.isEmpty {
                    subtasksListCard
                }
                if !draft.tags.isEmpty {
                    WrappingChipLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(draft.tags, id: \.self) { tag in
                            if isNotionLocked {
                                TaskEditorReadOnlyTagChip(title: tag)
                            } else {
                                TaskEditorTagChip(title: tag) {
                                    draft.tags.removeAll { $0 == tag }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    var primaryProperties: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            WrappingChipLayout(spacing: 8, lineSpacing: 8) {
                statusChip
                priorityChip
                typeChip
                projectChip
                durationChip
                dueChip
            }

            Divider()
                .background(CueInColors.divider)

            VStack(spacing: 0) {
                compactPropertyRow(icon: "square.grid.2x2.fill", title: "Initiative") {
                    fieldMenu
                }
            }
        }
        .padding(CueInSpacing.md)
        .cueInEditorGlassSurface(cornerRadius: 26)
    }

    var advancedSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            Text("Planning")
                .font(CueInTypography.captionMedium)
                .foregroundStyle(CueInColors.textTertiary)

            VStack(spacing: 0) {
                compactPropertyRow(icon: "calendar", title: "Start date") {
                    scheduledDateControl
                }
                compactDivider
                compactPropertyRow(icon: "calendar.badge.exclamationmark", title: "Due date") {
                    dueDateControl
                }
                compactDivider
                compactPropertyRow(icon: "arrow.clockwise", title: "Repeat") {
                    recurrenceMenu
                }
                compactDivider
                compactPropertyRow(icon: "archivebox", title: "Save to archive") {
                    Toggle("", isOn: $draft.savesToArchive)
                        .labelsHidden()
                        .tint(CueInColors.accentFocus)
                }

            }
            .padding(.vertical, 2)
            .cueInEditorGlassSurface(cornerRadius: 22)
        }
    }

    var editorAccessory: some View {
        VStack(spacing: 9) {
            if let accessoryPanel {
                accessoryPanelView(accessoryPanel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack {
                Spacer()
                subtaskFloatingButton
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if !isNotionLocked {
                        workTypeAccessory
                        durationAccessory
                        dateAccessory
                        repeatAccessory
                        tagAccessory
                        archiveAccessory
                    }
                    if case .edit = mode {
                        deleteAccessory
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .scrollClipDisabled()
            .cueInEditorGlassSurface(cornerRadius: 26)
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            LinearGradient(
                colors: [
                    CueInColors.background.opacity(0),
                    CueInColors.background.opacity(0.86),
                    CueInColors.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.18), value: accessoryPanel)
    }

    @ViewBuilder
    func accessoryPanelView(_ panel: TaskEditorAccessoryPanel) -> some View {
        switch panel {
        case .dates:
            if isNotionLocked {
                EmptyView()
            } else {
            VStack(spacing: 0) {
                datePickerRow(
                    title: "Start",
                    icon: "calendar",
                    tint: CueInColors.accentFocus,
                    date: Binding(
                        get: { draft.scheduledDate ?? Date() },
                        set: { setStartDate($0) }
                    ),
                    isSet: draft.scheduledDate != nil,
                    clear: clearStartDate
                )

                Divider()
                    .background(CueInColors.divider)
                    .padding(.leading, 44)

                datePickerRow(
                    title: "Due",
                    icon: "calendar.badge.exclamationmark",
                    tint: CueInColors.accentFixed,
                    date: Binding(
                        get: { draft.dueDate ?? Date() },
                        set: { draft.dueDate = $0 }
                    ),
                    isSet: draft.dueDate != nil,
                    clear: { draft.dueDate = nil }
                )
            }
            .padding(.vertical, 4)
            .cueInEditorGlassSurface(cornerRadius: 18)
            }

        case .tags:
            if isNotionLocked {
                EmptyView()
            } else {
            HStack(spacing: CueInSpacing.sm) {
                TextField("Add tag", text: $newTagText)
                    .font(CueInTypography.body)
                    .foregroundStyle(CueInColors.textPrimary)
                    .submitLabel(.done)
                    .onSubmit(addTag)

                Button(action: addTag) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                }
                .disabled(!canAddTag)
                .foregroundStyle(canAddTag ? CueInColors.accentFocus : CueInColors.textTertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .cueInEditorGlassSurface(cornerRadius: 18)
            }

        case .subtasks:
            if isNotionLocked {
                EmptyView()
            } else {
            HStack(spacing: CueInSpacing.sm) {
                TextField("Add sub-task", text: $newSubtaskTitle)
                    .font(CueInTypography.body)
                    .foregroundStyle(CueInColors.textPrimary)
                    .submitLabel(.done)
                    .onSubmit(addSubtask)

                Button(action: addSubtask) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                }
                .disabled(!canAddSubtask)
                .foregroundStyle(canAddSubtask ? CueInColors.accentFocus : CueInColors.textTertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .cueInEditorGlassSurface(cornerRadius: 18)
            }
        }
    }

    func datePickerRow(
        title: String,
        icon: String,
        tint: Color,
        date: Binding<Date>,
        isSet: Bool,
        clear: @escaping () -> Void
    ) -> some View {
        HStack(spacing: CueInSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSet ? tint : CueInColors.textTertiary)
                .frame(width: 22)

            Text(title)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textSecondary)

            Spacer(minLength: CueInSpacing.sm)

            DatePicker("", selection: date, displayedComponents: [.date])
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(tint)
                .opacity(isSet ? 1 : 0.62)

            Button(action: clear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CueInColors.textTertiary)
            }
            .buttonStyle(.plain)
            .opacity(isSet ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }
}

// MARK: - Chips

private extension TaskDetailSheet {
    var workTypeAccessory: some View {
        Menu {
            Button {
                draft.executionType = nil
            } label: {
                Label("None", systemImage: "xmark")
            }
            ForEach(TaskExecutionType.allCases) { type in
                Button { setExecutionType(type) } label: {
                    Label(type.label, systemImage: type.icon)
                }
            }
        } label: {
            TaskEditorAccessoryButton(
                icon: draft.executionType?.icon ?? "circle.dashed",
                tint: draft.executionType != nil ? CueInColors.textPrimary : CueInColors.textSecondary
            )
        }
    }

    var durationAccessory: some View {
        Menu {
            Button { draft.estimatedMinutes = nil } label: { Label("No duration", systemImage: "xmark") }
            ForEach([10, 15, 20, 25, 30, 45, 60, 90, 120], id: \.self) { minutes in
                Button { draft.estimatedMinutes = minutes } label: {
                    Text("\(minutes) min")
                }
            }
        } label: {
            TaskEditorAccessoryButton(icon: "clock", tint: CueInColors.textSecondary)
        }
    }

    var dateAccessory: some View {
        Button {
            accessoryPanel = accessoryPanel == .dates ? nil : .dates
        } label: {
            TaskEditorAccessoryButton(
                icon: "calendar",
                tint: hasAnyDate ? CueInColors.accentFocus : CueInColors.textSecondary
            )
        }
        .buttonStyle(.plain)
    }

    var repeatAccessory: some View {
        Menu {
            ForEach(TaskRecurrence.allCases) { recurrence in
                Button { draft.recurrence = recurrence } label: {
                    Text(recurrence.label)
                }
            }
        } label: {
            TaskEditorAccessoryButton(
                icon: "arrow.clockwise",
                tint: draft.recurrence == .none ? CueInColors.textSecondary : CueInColors.accentRoutine
            )
        }
    }

    var tagAccessory: some View {
        Button {
            accessoryPanel = accessoryPanel == .tags ? nil : .tags
        } label: {
            TaskEditorAccessoryButton(
                icon: "tag",
                tint: draft.tags.isEmpty ? CueInColors.textSecondary : CueInColors.accentFixed
            )
        }
        .buttonStyle(.plain)
    }

    var subtaskFloatingButton: some View {
        Button {
            accessoryPanel = accessoryPanel == .subtasks ? nil : .subtasks
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "checklist")
                    .font(.system(size: 14, weight: .semibold))
                if !draft.subtasks.isEmpty {
                    Text("\(draft.subtasks.filter(\.isCompleted).count)/\(draft.subtasks.count)")
                        .font(CueInTypography.micro)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(draft.subtasks.isEmpty ? CueInColors.textSecondary : CueInColors.success)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .cueInEditorGlassCapsule()
        }
        .buttonStyle(.plain)
    }

    var archiveAccessory: some View {
        Button {
            draft.savesToArchive.toggle()
        } label: {
            TaskEditorAccessoryButton(
                icon: "archivebox",
                tint: draft.savesToArchive ? CueInColors.accentFocus : CueInColors.textTertiary
            )
        }
        .buttonStyle(.plain)
    }

    var deleteAccessory: some View {
        Button(role: .destructive) {
            showingDelete = true
        } label: {
            TaskEditorAccessoryButton(icon: "trash", tint: CueInColors.danger)
        }
        .buttonStyle(.plain)
    }

    var statusChip: some View {
        Button {
            isStatusPopoverPresented = true
        } label: {
            TaskEditorPropertyChip(
                icon: draft.status.icon,
                title: draft.status.label,
                tint: draft.status.color
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isStatusPopoverPresented) {
            CueInTaskStatusPopoverContent(selection: draft.status) { status in
                isStatusPopoverPresented = false
                setStatus(status)
            }
        }
    }

    var priorityChip: some View {
        Menu {
            ForEach(TaskPriority.allCases) { priority in
                Button {
                    draft.priority = priority
                } label: {
                    Label(priority.label, systemImage: priority.icon)
                }
            }
        } label: {
            TaskEditorPropertyChip(
                icon: draft.priority.icon,
                title: draft.priority.shortLabel,
                tint: draft.priority.color
            )
        }
    }

    var typeChip: some View {
        Menu {
            Button {
                draft.executionType = nil
            } label: {
                Label("None", systemImage: "xmark")
            }
            ForEach(TaskExecutionType.allCases) { type in
                Button {
                    setExecutionType(type)
                } label: {
                    Label(type.label, systemImage: type.icon)
                }
            }
        } label: {
            Image(systemName: draft.executionType?.icon ?? "circle.dashed")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(
                    draft.executionType != nil ? CueInColors.textPrimary : CueInColors.textSecondary
                )
                .padding(.horizontal, 11)
                .frame(height: 36)
                .cueInEditorGlassCapsule()
        }
    }

    var projectChip: some View {
        Menu {
            projectMenuContent
        } label: {
            TaskEditorPropertyChip(
                icon: store.project(draft.projectID)?.resolvedIconSystemName ?? "folder",
                title: store.project(draft.projectID)?.name ?? "Project",
                tint: projectTint
            )
        }
    }

    var fieldChip: some View {
        Menu {
            fieldMenuContent
        } label: {
            TaskEditorPropertyChip(
                icon: store.field(draft.fieldID)?.resolvedIconSystemName ?? "square.grid.2x2",
                title: store.field(draft.fieldID)?.name ?? "Initiative",
                tint: store.field(draft.fieldID)?.color ?? CueInColors.textSecondary
            )
        }
    }

    var durationChip: some View {
        Menu {
            Button { draft.estimatedMinutes = nil } label: { Text("Not set") }
            ForEach([10, 15, 20, 25, 30, 45, 60, 90, 120], id: \.self) { minutes in
                Button { draft.estimatedMinutes = minutes } label: {
                    Text("\(minutes) min")
                }
            }
        } label: {
            TaskEditorPropertyChip(
                icon: "clock",
                title: draft.estimatedMinutes.map { "\($0)m" } ?? "Duration",
                tint: CueInColors.textSecondary
            )
        }
    }

    var dueChip: some View {
        Menu {
            Button { draft.dueDate = nil } label: { Label("No due date", systemImage: "xmark") }
            Button { draft.dueDate = Date() } label: { Label("Today", systemImage: "sun.max") }
            Button {
                draft.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
            } label: {
                Label("Tomorrow", systemImage: "arrow.turn.up.right")
            }
        } label: {
            TaskEditorPropertyChip(
                icon: "calendar.badge.exclamationmark",
                title: dueChipTitle,
                tint: draft.dueDate == nil ? CueInColors.textSecondary : CueInColors.accentFixed
            )
        }
    }
}

// MARK: - Properties

private extension TaskDetailSheet {
    var fieldMenu: some View {
        Menu {
            Button {
                draft.fieldID = nil
                draft.projectID = nil
            } label: {
                Label("None", systemImage: "xmark")
            }

            ForEach(store.fields) { field in
                Button {
                    if draft.fieldID != field.id { draft.projectID = nil }
                    draft.fieldID = field.id
                } label: {
                    Label(field.name, systemImage: field.resolvedIconSystemName)
                }
            }
        } label: {
            compactValue(store.field(draft.fieldID)?.name ?? "None", tint: store.field(draft.fieldID)?.color)
        }
    }

    var scheduledDateControl: some View {
        HStack(spacing: 7) {
            if draft.scheduledDate != nil {
                Button {
                    draft.scheduledDate = nil
                    if draft.status == .scheduled || draft.status == .active || draft.status == .paused {
                        draft.status = .inbox
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(CueInColors.textTertiary)
                }
                .buttonStyle(.plain)
            }

            DatePicker(
                "",
                selection: Binding(
                    get: { draft.scheduledDate ?? Date() },
                    set: {
                        draft.scheduledDate = $0
                        if draft.status == .inbox { draft.status = .scheduled }
                    }
                ),
                displayedComponents: [.date]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(CueInColors.accentFocus)
            .opacity(draft.scheduledDate == nil ? 0.45 : 1)
            .onTapGesture {
                if draft.scheduledDate == nil {
                    draft.scheduledDate = Calendar.current.startOfDay(for: Date())
                    if draft.status == .inbox { draft.status = .scheduled }
                }
            }
        }
    }

    var dueDateControl: some View {
        HStack(spacing: 7) {
            if draft.dueDate != nil {
                Button {
                    draft.dueDate = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(CueInColors.textTertiary)
                }
                .buttonStyle(.plain)
            }

            DatePicker(
                "",
                selection: Binding(
                    get: { draft.dueDate ?? Date() },
                    set: { draft.dueDate = $0 }
                ),
                displayedComponents: [.date]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(CueInColors.accentFixed)
            .opacity(draft.dueDate == nil ? 0.45 : 1)
            .onTapGesture {
                if draft.dueDate == nil { draft.dueDate = Date() }
            }
        }
    }

    var recurrenceMenu: some View {
        Menu {
            ForEach(TaskRecurrence.allCases) { recurrence in
                Button {
                    draft.recurrence = recurrence
                } label: {
                    Text(recurrence.label)
                }
            }
        } label: {
            compactValue(draft.recurrence.label)
        }
    }

}

// MARK: - Tags

private extension TaskDetailSheet {
    var tagSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            Text("Tags")
                .font(CueInTypography.captionMedium)
                .foregroundStyle(CueInColors.textTertiary)

            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                WrappingChipLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(draft.tags, id: \.self) { tag in
                        TaskEditorTagChip(title: tag) {
                            draft.tags.removeAll { $0 == tag }
                        }
                    }
                }

                HStack(spacing: CueInSpacing.sm) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CueInColors.textTertiary)

                    TextField("Add tag", text: $newTagText)
                        .font(CueInTypography.body)
                        .foregroundStyle(CueInColors.textPrimary)
                        .submitLabel(.done)
                        .onSubmit(addTag)

                    Button("Add", action: addTag)
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(canAddTag ? CueInColors.accentFocus : CueInColors.textTertiary)
                        .disabled(!canAddTag)
                }
                .padding(.horizontal, CueInSpacing.md)
                .frame(height: 44)
                .background(CueInColors.surfacePrimary.opacity(0.48), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(CueInSpacing.md)
            .cueInEditorGlassSurface(cornerRadius: 22)
        }
    }

    func addTag() {
        let clean = newTagText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !clean.isEmpty, !draft.tags.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) else {
            newTagText = ""
            return
        }
        draft.tags.append(clean)
        newTagText = ""
    }
}

// MARK: - Subtasks

private extension TaskDetailSheet {
    /// Checklist card under the description; add flow stays on the checklist button + bottom panel.
    var subtasksListCard: some View {
        let rowH: CGFloat = 54
        let cap = 5

        return VStack(spacing: 0) {
            if draft.subtasks.count > cap {
                ScrollView {
                    subtaskListRows
                }
                .frame(maxHeight: rowH * CGFloat(cap))
            } else {
                subtaskListRows
            }
        }
        .cueInEditorGlassSurface(cornerRadius: 20)
    }

    private var subtaskListRows: some View {
        VStack(spacing: 0) {
            ForEach(draft.subtasks.indices, id: \.self) { index in
                subtaskRow(index: index)
                if index < draft.subtasks.indices.last ?? 0 {
                    Divider()
                        .background(CueInColors.divider)
                        .padding(.leading, 44)
                }
            }
        }
    }

    func subtaskRow(index: Int) -> some View {
        HStack(spacing: CueInSpacing.sm) {
            Button {
                guard !isNotionLocked else { return }
                draft.subtasks[index].isCompleted.toggle()
            } label: {
                Image(systemName: draft.subtasks[index].isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(draft.subtasks[index].isCompleted ? CueInColors.success : CueInColors.textTertiary)
            }
            .buttonStyle(.plain)

            TextField("Sub-task", text: Binding(
                get: { draft.subtasks[index].title },
                set: { draft.subtasks[index].title = $0 }
            ))
            .font(CueInTypography.body)
            .foregroundStyle(draft.subtasks[index].isCompleted ? CueInColors.textTertiary : CueInColors.textPrimary)
            .strikethrough(draft.subtasks[index].isCompleted, color: CueInColors.textTertiary)
            .disabled(isNotionLocked)

            if !isNotionLocked {
                Button {
                    draft.subtasks.remove(at: index)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CueInColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, CueInSpacing.md)
        .padding(.vertical, 11)
    }

    func addSubtask() {
        let clean = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        draft.subtasks.append(TaskSubtask(title: clean))
        newSubtaskTitle = ""
    }
}

// MARK: - Archive / Delete

private extension TaskDetailSheet {
    var archiveAndDeleteSection: some View {
        HStack(spacing: CueInSpacing.sm) {
            Button {
                setStatus(.archived)
                save()
            } label: {
                Label("Archive", systemImage: "archivebox")
                    .font(CueInTypography.bodyMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, CueInSpacing.md)
                    .background(CueInColors.surfacePrimary.opacity(0.54), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(CueInColors.textSecondary)

            Button(role: .destructive) {
                showingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(CueInTypography.bodyMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, CueInSpacing.md)
                    .background(CueInColors.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(CueInColors.danger)
        }
    }
}

// MARK: - Actions / Derived

private extension TaskDetailSheet {
    var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canAddTag: Bool {
        !isNotionLocked && !newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canAddSubtask: Bool {
        !isNotionLocked && !newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isNotionLocked: Bool {
        if case .edit = mode {
            return draft.isNotionImported
        }
        return false
    }

    var deleteAlertTitle: String {
        isNotionLocked ? "Archive Notion task in CueIn?" : "Delete task?"
    }

    var deleteAlertActionTitle: String {
        isNotionLocked ? "Archive in CueIn" : "Delete"
    }

    var deleteAlertMessage: String {
        if isNotionLocked {
            return "This will not delete the task in Notion. It only moves the local CueIn copy to Archive."
        }
        return "This can't be undone."
    }

    var projectTint: Color {
        store.project(draft.projectID).map { store.color(for: $0) } ?? CueInColors.textSecondary
    }

    var organizationTitle: String {
        if let project = store.project(draft.projectID) {
            return project.name
        }
        if let field = store.field(draft.fieldID) {
            return field.name
        }
        return "No project"
    }

    var organizationIcon: String {
        if let project = store.project(draft.projectID) {
            return project.resolvedIconSystemName
        }
        if let field = store.field(draft.fieldID) {
            return field.resolvedIconSystemName
        }
        return "folder"
    }

    var organizationTint: Color {
        if let project = store.project(draft.projectID) {
            return store.color(for: project)
        }
        if let field = store.field(draft.fieldID) {
            return field.color
        }
        return CueInColors.textSecondary
    }

    var dueChipTitle: String {
        guard let dueDate = draft.dueDate else { return "Due date" }
        if Calendar.current.isDateInToday(dueDate) { return "Today" }
        if Calendar.current.isDateInTomorrow(dueDate) { return "Tomorrow" }
        return dueDate.formatted(date: .abbreviated, time: .omitted)
    }

    var hasAnyDate: Bool {
        draft.scheduledDate != nil || draft.dueDate != nil
    }

    @ViewBuilder
    var projectMenuContent: some View {
        Button {
            draft.projectID = nil
        } label: {
            Label("No project", systemImage: "xmark")
        }

        let relevant = draft.fieldID.map(store.projects) ?? store.projects
        ForEach(relevant) { project in
            Button {
                draft.projectID = project.id
                if draft.fieldID == nil { draft.fieldID = project.fieldID }
            } label: {
                Label(project.name, systemImage: project.resolvedIconSystemName)
            }
        }
    }

    @ViewBuilder
    var fieldMenuContent: some View {
        Button {
            draft.fieldID = nil
            draft.projectID = nil
        } label: {
            Label("None", systemImage: "xmark")
        }

        ForEach(store.fields) { field in
            Button {
                if draft.fieldID != field.id { draft.projectID = nil }
                draft.fieldID = field.id
            } label: {
                Label(field.name, systemImage: field.resolvedIconSystemName)
            }
        }
    }

    var compactDivider: some View {
        Divider()
            .background(CueInColors.divider)
            .padding(.leading, CueInSpacing.base + 18 + CueInSpacing.md)
    }

    func compactPropertyRow<Trailing: View>(
        icon: String,
        title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: CueInSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CueInColors.textTertiary)
                .frame(width: 18)

            Text(title)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textSecondary)

            Spacer(minLength: CueInSpacing.md)

            trailing()
        }
        .padding(.horizontal, CueInSpacing.md)
        .padding(.vertical, 11)
    }

    func compactValue(_ text: String, tint: Color? = nil) -> some View {
        HStack(spacing: 6) {
            if let tint {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textPrimary)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CueInColors.textTertiary)
        }
    }

    func setExecutionType(_ type: TaskExecutionType) {
        withAnimation(.easeInOut(duration: 0.15)) {
            draft.executionType = type
        }
    }

    func setStartDate(_ date: Date) {
        draft.scheduledDate = date
        if draft.status == .inbox { draft.status = .scheduled }
    }

    func clearStartDate() {
        draft.scheduledDate = nil
        if draft.status == .scheduled || draft.status == .active || draft.status == .paused {
            draft.status = .inbox
        }
    }

    func setStatus(_ status: TaskStatus) {
        guard draft.status != status else { return }
        draft.status = status
        switch status {
        case .inbox:
            draft.completedAt = nil
        case .scheduled:
            if draft.scheduledDate == nil {
                draft.scheduledDate = Calendar.current.startOfDay(for: Date())
            }
            draft.completedAt = nil
        case .active:
            if draft.scheduledDate == nil {
                draft.scheduledDate = Calendar.current.startOfDay(for: Date())
            }
            draft.completedAt = nil
        case .paused:
            if draft.scheduledDate == nil {
                draft.scheduledDate = Calendar.current.startOfDay(for: Date())
            }
            draft.completedAt = nil
        case .completed:
            draft.completedAt = draft.completedAt ?? Date()
        case .archived:
            break
        }
    }

    func save() {
        normalizeDraftForSave()
        draft.updatedAt = Date()

        switch mode {
        case .create:
            store.addTask(draft)
            onCreated?(draft)
        case .edit:
            store.updateTask(draft)
        }
        onDismiss()
    }

    func normalizeDraftForSave() {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.tags = draft.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .filter { !$0.isEmpty }
        draft.subtasks = draft.subtasks.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        switch draft.status {
        case .completed:
            draft.completedAt = draft.completedAt ?? Date()
        case .scheduled:
            draft.scheduledDate = draft.scheduledDate ?? Calendar.current.startOfDay(for: Date())
            draft.completedAt = nil
        case .active:
            draft.scheduledDate = draft.scheduledDate ?? Calendar.current.startOfDay(for: Date())
            draft.completedAt = nil
        case .paused:
            draft.scheduledDate = draft.scheduledDate ?? Calendar.current.startOfDay(for: Date())
            draft.completedAt = nil
        case .inbox:
            draft.completedAt = nil
        case .archived:
            break
        }
    }

    func focusTitleOnce() {
        guard !isNotionLocked else { return }
        guard !didRequestInitialFocus else { return }
        didRequestInitialFocus = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            titleFocused = true
        }
    }
}

// MARK: - Supporting Views

private struct TaskEditorPropertyChip: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(CueInTypography.captionMedium)
                .foregroundStyle(CueInColors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
        .cueInEditorGlassCapsule()
    }
}

private struct TaskEditorAccessoryButton: View {
    let icon: String
    let tint: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 42, height: 34)
            .contentShape(Rectangle())
    }
}

private struct TaskEditorTagChip: View {
    let title: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Text(initial)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(tagColor, in: Circle())
            Text(title)
                .font(CueInTypography.captionMedium)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(CueInColors.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(CueInColors.surfacePrimary.opacity(0.54), in: Capsule(style: .continuous))
    }

    private var initial: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "#"
    }

    private var tagColor: Color {
        let palette = [
            CueInColors.accentFocus,
            CueInColors.accentRoutine,
            CueInColors.accentFixed,
            CueInColors.success,
            CueInColors.warning,
            CueInColors.danger
        ]
        let total = title.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[abs(total) % palette.count]
    }
}

private struct TaskEditorReadOnlyTagChip: View {
    let title: String

    var body: some View {
        Text("#\(title)")
            .font(CueInTypography.captionMedium)
            .foregroundStyle(CueInColors.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(CueInColors.surfacePrimary.opacity(0.48), in: Capsule(style: .continuous))
    }
}

private struct WrappingChipLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        let rows = rows(maxWidth: maxWidth, subviews: subviews)
        let height = rows.reduce(CGFloat.zero) { partial, row in
            partial + row.height
        } + CGFloat(max(rows.count - 1, 0)) * lineSpacing
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                let size = item.size
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var currentWidth: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = current.items.isEmpty ? size.width : currentWidth + spacing + size.width
            if nextWidth > maxWidth, !current.items.isEmpty {
                rows.append(current)
                current = Row()
                currentWidth = 0
            }

            current.items.append(RowItem(index: index, size: size))
            currentWidth = current.items.count == 1 ? size.width : currentWidth + spacing + size.width
            current.height = max(current.height, size.height)
        }

        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }

    private struct Row {
        var items: [RowItem] = []
        var height: CGFloat = 0
    }

    private struct RowItem {
        let index: Int
        let size: CGSize
    }
}

#Preview {
    TaskDetailSheet(mode: .create, store: .shared) { }
}
