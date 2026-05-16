import SwiftUI

enum TasksDisplayDensity: String, CaseIterable, Identifiable {
    case minimal
    case compact
    case detailed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minimal: return "Minimal"
        case .compact: return "Compact"
        case .detailed: return "Detailed"
        }
    }

    var rowVerticalPadding: CGFloat {
        switch self {
        case .minimal: return 6
        case .compact: return 9
        case .detailed: return 13
        }
    }

    var titleFontSize: CGFloat {
        switch self {
        case .minimal: return 14
        case .compact: return 15
        case .detailed: return 16
        }
    }

    var metaFontSize: CGFloat {
        switch self {
        case .minimal: return 10
        case .compact: return 11
        case .detailed: return 12
        }
    }
}

enum TasksMetadataLevel: String, CaseIterable, Identifiable {
    case minimal
    case balanced
    case full

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minimal: return "Minimal"
        case .balanced: return "Balanced"
        case .full: return "Full"
        }
    }
}

enum TasksTaskDisplayPrefs {
    static let densityKey = "cuein.tasks.display.density"
    static let metadataKey = "cuein.tasks.display.metadata"
    static let showProjectKey = "cuein.tasks.display.showProject"
    static let showDueKey = "cuein.tasks.display.showDue"
    static let showEstimateKey = "cuein.tasks.display.showEstimate"
    static let showPriorityKey = "cuein.tasks.display.showPriority"
}

struct TasksHomeView: View {
    let store: TasksStore
    let onCreateTask: (TaskDraftDefaults) -> Void
    let onOpenTask: (UUID) -> Void
    let onOpenSearch: () -> Void
    let onCreateField: () -> Void
    let onCreateProject: (UUID?) -> Void
    let onPoolMove: (TaskItem, Bool) -> Void
    let onDeleteTask: (TaskItem, String) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedWorklist: TasksWorklistKind = .tasks
    @State private var sidebarPresented = false
    @State private var actionTask: TaskItem?

    private var usesPersistentSidebar: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                if usesPersistentSidebar {
                    sidebar
                        .frame(width: 286)
                    divider
                }
                worklist
                    .accessibilityHidden(sidebarPresented && !usesPersistentSidebar)
            }

            if !usesPersistentSidebar {
                Color.black.opacity(sidebarPresented ? 0.3 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { closeSidebar() }
                    .allowsHitTesting(sidebarPresented)

                sidebar
                    .frame(width: min(340, UIScreen.main.bounds.width * 0.86))
                    .offset(x: sidebarPresented ? 0 : -min(340, UIScreen.main.bounds.width * 0.86))
            }
        }
        .animation(.snappy(duration: 0.25, extraBounce: 0), value: sidebarPresented)
        .sheet(item: $actionTask) { task in
            TaskRowActionsSheet(
                task: task,
                store: store,
                onDismiss: {
                    actionTask = nil
                },
                onOpen: {
                    actionTask = nil
                    onOpenTask(task.id)
                },
                onDelete: {
                    actionTask = nil
                    onDeleteTask(task, listKey)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
    }
}

private extension TasksHomeView {
    var worklist: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if visibleTasks.isEmpty {
                TaskEmptyPanel(
                    icon: selectedEmptyIcon,
                    title: selectedEmptyTitle,
                    actionTitle: "New task",
                    action: { onCreateTask(defaultsForCreate) }
                )
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.top, CueInSpacing.xl)
            } else {
                ReorderableTaskList(
                    tasks: visibleTasks,
                    listKey: listKey,
                    onOpenTask: onOpenTask,
                    onPoolMove: onPoolMove,
                    onDeleteTask: onDeleteTask,
                    onMoreActions: { task in actionTask = task }
                )
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.top, CueInSpacing.md)
                .padding(.bottom, CueInLayout.scrollBottomInset)
            }
        }
        .background(CueInColors.background.ignoresSafeArea())
        .navigationTitle(selectedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !usesPersistentSidebar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        sidebarPresented.toggle()
                    } label: {
                        Image(systemName: sidebarPresented ? "xmark" : "sidebar.left")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(CueInColors.textPrimary)
                    }
                    .accessibilityLabel(sidebarPresented ? "Close library" : "Open task library")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onCreateTask(defaultsForCreate)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(CueInColors.textPrimary)
                }
                .accessibilityLabel("New task")
            }
        }
    }

    var sidebar: some View {
        TasksLinearSidebar(
            store: store,
            selectedWorklist: selectedWorklist,
            onSelectWorklist: { kind in
                selectedWorklist = kind
                closeSidebar()
            },
            onCreateField: {
                closeSidebar()
                onCreateField()
            },
            onCreateProject: { fieldID in
                closeSidebar()
                onCreateProject(fieldID)
            },
            showsCloseButton: !usesPersistentSidebar,
            onClose: closeSidebar
        )
    }

    var divider: some View {
        Rectangle()
            .fill(CueInColors.divider.opacity(0.7))
            .frame(width: 1)
            .ignoresSafeArea(edges: .vertical)
    }

    func closeSidebar() {
        sidebarPresented = false
    }

}

private extension TasksHomeView {
    var visibleTasks: [TaskItem] {
        switch selectedWorklist {
        case .tasks:
            return tasksList
        case .collection(.today):
            return store.todayTasks.filter { !$0.isCompleted }
        case .collection(.inbox):
            return store.inboxTasks
        case .collection(.upcoming):
            return store.upcomingTasks
        case .collection(.all):
            return store.tasks.filter { $0.status != .archived }
        case .completed:
            return store.tasks
                .filter(\.isCompleted)
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        case .archived:
            return store.tasks
                .filter { $0.status == .archived }
                .sorted { $0.updatedAt > $1.updatedAt }
        case .saved:
            return store.tasks
                .filter(\.savesToArchive)
                .sorted { $0.updatedAt > $1.updatedAt }
        case .habits:
            return store.activeTasks
                .filter { $0.tags.contains("habit") || $0.recurrence != .none }
                .sorted(by: actionSort)
        case .rituals:
            return store.activeTasks
                .filter { $0.tags.contains("ritual") || $0.tags.contains("routine") }
                .sorted(by: actionSort)
        case .field(let id):
            return store.activeTasks
                .filter { $0.fieldID == id }
                .sorted(by: actionSort)
        case .project(let id):
            return store.activeTasks
                .filter { $0.projectID == id }
                .sorted(by: actionSort)
        }
    }

    var tasksList: [TaskItem] {
        store.activeTasks.sorted(by: actionSort)
    }

    func actionSort(_ a: TaskItem, _ b: TaskItem) -> Bool {
        let aw = actionWeight(a)
        let bw = actionWeight(b)
        if aw != bw { return aw < bw }
        if a.priority.sortWeight != b.priority.sortWeight {
            return a.priority.sortWeight < b.priority.sortWeight
        }
        let ad = a.dueDate ?? a.scheduledDate ?? .distantFuture
        let bd = b.dueDate ?? b.scheduledDate ?? .distantFuture
        if ad != bd { return ad < bd }
        return a.createdAt < b.createdAt
    }

    func actionWeight(_ task: TaskItem) -> Int {
        if task.status == .active { return 0 }
        if task.status == .paused { return 1 }
        if task.isOverdue { return 2 }
        if task.priority == .urgent { return 3 }
        if task.priority == .high { return 4 }
        if task.isScheduledToday { return 5 }
        if isUpcomingSoon(task) { return 6 }
        if task.isInboxed { return 7 }
        return 8
    }

    func isUpcomingSoon(_ task: TaskItem) -> Bool {
        guard let scheduled = task.scheduledDate else { return false }
        let start = Calendar.current.startOfDay(for: Date())
        guard let limit = Calendar.current.date(byAdding: .day, value: 7, to: start) else { return false }
        return scheduled > start && scheduled <= limit
    }

    var defaultsForCreate: TaskDraftDefaults {
        switch selectedWorklist {
        case .collection(.today):
            return .today()
        case .collection(.upcoming):
            return .upcoming()
        case .field(let id):
            if let field = store.field(id) { return .field(field) }
            return .inbox
        case .project(let id):
            if let project = store.project(id) { return .project(project) }
            return .inbox
        default:
            return .inbox
        }
    }

    var listKey: String {
        switch selectedWorklist {
        case .tasks: return "tasks-worklist:tasks"
        case .collection(let kind): return kind.listKeyPrefix
        case .completed: return "tasks-worklist:completed"
        case .archived: return "tasks-worklist:archived"
        case .saved: return "tasks-worklist:saved"
        case .habits: return "tasks-worklist:habits"
        case .rituals: return "tasks-worklist:rituals"
        case .field(let id): return "tasks-worklist:field:\(id.uuidString)"
        case .project(let id): return "tasks-worklist:project:\(id.uuidString)"
        }
    }

    var selectedTitle: String {
        switch selectedWorklist {
        case .tasks: return "Tasks"
        case .collection(let kind): return kind.shortTitle
        case .completed: return "Completed"
        case .archived: return "Archive"
        case .saved: return "Saved"
        case .habits: return "Habits"
        case .rituals: return "Rituals"
        case .field(let id): return store.field(id)?.name ?? "Field"
        case .project(let id): return store.project(id)?.name ?? "Project"
        }
    }

    var selectedEmptyIcon: String {
        switch selectedWorklist {
        case .tasks: return "checkmark.circle"
        case .collection(.today): return "sun.max"
        case .collection(.inbox): return "tray"
        case .collection(.upcoming): return "calendar"
        case .collection(.all): return "tray.full"
        case .completed: return "checkmark.circle"
        case .archived: return "archivebox"
        case .saved: return "bookmark"
        case .habits: return "repeat"
        case .rituals: return "sparkles"
        case .field: return "square.grid.2x2"
        case .project: return "folder"
        }
    }

    var selectedEmptyTitle: String {
        switch selectedWorklist {
        case .tasks: return "No tasks"
        case .collection(.today): return "To-do is clear"
        case .collection(.inbox): return "Inbox is clear"
        case .collection(.upcoming): return "Nothing scheduled"
        case .collection(.all): return "No tasks"
        case .completed: return "Nothing completed"
        case .archived: return "Archive is empty"
        case .saved: return "Nothing saved"
        case .habits: return "No habits yet"
        case .rituals: return "No rituals yet"
        case .field: return "No active tasks"
        case .project: return "No project tasks"
        }
    }
}



private struct TasksLinearSidebar: View {
    let store: TasksStore
    let selectedWorklist: TasksWorklistKind
    let onSelectWorklist: (TasksWorklistKind) -> Void
    let onCreateField: () -> Void
    let onCreateProject: (UUID?) -> Void
    let showsCloseButton: Bool
    let onClose: () -> Void
    @AppStorage(TasksTaskDisplayPrefs.densityKey) private var densityRaw = TasksDisplayDensity.compact.rawValue
    @AppStorage(TasksTaskDisplayPrefs.metadataKey) private var metadataRaw = TasksMetadataLevel.balanced.rawValue
    @AppStorage(TasksTaskDisplayPrefs.showProjectKey) private var showProject = true
    @AppStorage(TasksTaskDisplayPrefs.showDueKey) private var showDue = true
    @AppStorage(TasksTaskDisplayPrefs.showEstimateKey) private var showEstimate = true
    @AppStorage(TasksTaskDisplayPrefs.showPriorityKey) private var showPriority = true

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.lg) {
            sidebarHeader

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: CueInSpacing.base) {
                    sidebarSection("Tasks") {
                        sidebarRow(.tasks, title: "Tasks", icon: "checklist", count: tasksCount)
                        sidebarRow(.collection(.today), title: "To-do", icon: "circle.grid.2x2", count: store.todayTasks.filter { !$0.isCompleted }.count)
                        sidebarRow(.collection(.inbox), title: "Inbox", icon: "tray", count: store.inboxTasks.count)
                        sidebarRow(.collection(.upcoming), title: "Upcoming", icon: "calendar", count: store.upcomingTasks.count)
                    }

                    sidebarSection("Plan") {
                        sidebarRouteRow(title: "Projects", icon: "folder", route: .projects, count: store.projects.count)
                        sidebarRouteRow(title: "Fields", icon: "square.grid.2x2", route: .initiatives, count: store.fields.count)
                    }

                    sidebarSection("Rhythm") {
                        sidebarRow(.habits, title: "Habits", icon: "repeat", count: habitsCount)
                        sidebarRow(.rituals, title: "Rituals", icon: "sparkles", count: ritualsCount)
                    }

                    sidebarSection("Library") {
                        sidebarRow(.saved, title: "Saved", icon: "bookmark", count: store.tasks.filter(\.savesToArchive).count)
                        sidebarRow(.archived, title: "Archive", icon: "archivebox", count: store.tasks.filter { $0.status == .archived }.count)
                        sidebarRow(.completed, title: "Completed", icon: "checkmark.circle", count: store.tasks.filter(\.isCompleted).count)
                        sidebarRow(.collection(.all), title: "All", icon: "list.bullet", count: store.tasks.filter { $0.status != .archived }.count)
                    }
                }
                .padding(.horizontal, CueInSpacing.md)
                .padding(.bottom, CueInLayout.scrollBottomInset)
            }
        }
        .padding(.top, CueInSpacing.base)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(CueInColors.surfacePrimary.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(CueInColors.divider.opacity(0.75))
                .frame(width: 1)
                .ignoresSafeArea(edges: .vertical)
        }
    }

    private var sidebarHeader: some View {
        HStack {
            Spacer()
            Menu {
                displayMenuContent
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(CueInColors.textSecondary)
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Customize task display")
        }
        .padding(.horizontal, CueInSpacing.base)
        .padding(.bottom, CueInSpacing.xs)
    }

    @ViewBuilder
    private var displayMenuContent: some View {
        Picker("Density", selection: $densityRaw) {
            ForEach(TasksDisplayDensity.allCases) { density in
                Text(density.label).tag(density.rawValue)
            }
        }

        Picker("Information", selection: $metadataRaw) {
            ForEach(TasksMetadataLevel.allCases) { level in
                Text(level.label).tag(level.rawValue)
            }
        }

        Divider()

        Toggle("Show project", isOn: $showProject)
        Toggle("Show dates", isOn: $showDue)
        Toggle("Show estimate", isOn: $showEstimate)
        Toggle("Show priority", isOn: $showPriority)
    }

    private var tasksCount: Int {
        store.activeTasks.count
    }

    private var habitsCount: Int {
        store.activeTasks.filter { $0.tags.contains("habit") || $0.recurrence != .none }.count
    }

    private var ritualsCount: Int {
        store.activeTasks.filter { $0.tags.contains("ritual") || $0.tags.contains("routine") }.count
    }

    private func sidebarSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: CueInSpacing.xs) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CueInColors.textTertiary)
                .padding(.horizontal, CueInSpacing.xs)

            VStack(spacing: 1) {
                content()
            }
            .padding(5)
            .background(CueInColors.surfaceSecondary.opacity(0.48))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(CueInColors.divider.opacity(0.55), lineWidth: 0.5)
            }
        }
    }

    private func sidebarRow(
        _ kind: TasksWorklistKind,
        title: String,
        icon: String,
        count: Int,
        tint: Color = CueInColors.textSecondary
    ) -> some View {
        Button {
            onSelectWorklist(kind)
        } label: {
            sidebarRowContent(
                title: title,
                icon: icon,
                count: count,
                isSelected: selectedWorklist == kind,
                tint: tint
            )
        }
        .buttonStyle(.plain)
    }

    private func sidebarRouteRow(title: String, icon: String, route: TasksRoute, count: Int) -> some View {
        NavigationLink(value: route) {
            sidebarRowContent(
                title: title,
                icon: icon,
                count: count,
                isSelected: false,
                tint: CueInColors.textSecondary
            )
        }
        .buttonStyle(.plain)
    }

    private func sidebarRowContent(
        title: String,
        icon: String,
        count: Int,
        isSelected: Bool,
        tint: Color
    ) -> some View {
        HStack(spacing: CueInSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: icon == "circle.fill" ? 6 : 13, weight: .semibold))
                .foregroundStyle(tint.opacity(isSelected ? 0.95 : 0.62))
                .frame(width: 22)

            Text(title)
                .font(CueInTypography.bodyMedium)
                .foregroundStyle(isSelected ? CueInColors.textPrimary : CueInColors.textSecondary)
                .lineLimit(1)

            Spacer(minLength: CueInSpacing.sm)

            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CueInColors.textTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, CueInSpacing.sm)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? CueInColors.surfacePrimary.opacity(0.95) : Color.clear)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(CueInColors.divider.opacity(0.55), lineWidth: 0.5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct TaskRowActionsSheet: View {
    let task: TaskItem
    let store: TasksStore
    let onDismiss: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        CueInBottomSheet(title: "Task", onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                SheetActionRow(icon: "pencil", title: "Edit", subtitle: task.title, action: onOpen)

                SheetActionRow(icon: "sun.max", title: "Schedule today", subtitle: "Move into today") {
                    store.scheduleTask(task.id, on: Calendar.current.startOfDay(for: Date()))
                    onDismiss()
                }

                SheetActionRow(icon: "tray", title: "Move to inbox", subtitle: "Clear schedule") {
                    store.scheduleTask(task.id, on: nil)
                    onDismiss()
                }

                Menu {
                    ForEach(TaskPriority.allCases) { priority in
                        Button {
                            store.setTaskPriority(id: task.id, priority: priority)
                            onDismiss()
                        } label: {
                            Label(priority.label, systemImage: priority.icon)
                        }
                    }
                } label: {
                    actionMenuRow(icon: "flame", title: "Priority", value: task.priority.label)
                }

                Menu {
                    Button("No project") {
                        var next = task
                        next.projectID = nil
                        next.fieldID = nil
                        store.updateTask(next)
                        onDismiss()
                    }
                    ForEach(store.projects) { project in
                        Button(project.name) {
                            var next = task
                            next.projectID = project.id
                            next.fieldID = project.fieldID
                            store.updateTask(next)
                            onDismiss()
                        }
                    }
                } label: {
                    actionMenuRow(icon: "folder", title: "Project", value: store.project(task.projectID)?.name ?? "None")
                }

                Divider()
                    .overlay(CueInColors.divider)
                    .padding(.vertical, CueInSpacing.xs)

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(CueInTypography.bodyMedium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, CueInSpacing.sm)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actionMenuRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: CueInSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CueInColors.textSecondary)
                .frame(width: 24)
            Text(title)
                .font(CueInTypography.bodyMedium)
                .foregroundStyle(CueInColors.textPrimary)
            Spacer()
            Text(value)
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CueInColors.textTertiary)
        }
        .padding(.vertical, CueInSpacing.sm)
        .contentShape(Rectangle())
    }
}

struct TaskSectionHeader: View {
    let title: String
    let icon: String
    let tint: Color
    var trailing: AnyView?

    init(title: String, icon: String, tint: Color, trailing: AnyView? = nil) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CueInColors.textTertiary)
            Text(title.uppercased())
                .font(Font.system(size: 10, weight: .semibold))
                .foregroundStyle(CueInColors.textTertiary)
            Spacer(minLength: CueInSpacing.sm)
            if let trailing {
                trailing
            }
        }
    }
}

struct TaskEmptyPanel: View {
    let icon: String
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: CueInSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(CueInColors.textTertiary)
            Text(title)
                .font(CueInTypography.captionMedium)
                .foregroundStyle(CueInColors.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CueInSpacing.xl)
        .background(CueInColors.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                .strokeBorder(CueInColors.cardBorder, lineWidth: 0.6)
        }
    }
}
