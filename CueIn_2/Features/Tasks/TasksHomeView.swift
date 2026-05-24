import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

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

struct TasksHomeView<RouteDestination: View>: View {
    let store: TasksStore
    let onCreateTask: (TaskDraftDefaults) -> Void
    let onOpenTask: (UUID) -> Void
    let onOpenSearch: () -> Void
    let onCreateField: () -> Void
    let onCreateProject: (UUID?) -> Void
    let onPoolMove: (TaskItem, Bool) -> Void
    let onDeleteTask: (TaskItem, String) -> Void
    let onOpenSettings: () -> Void
    @ViewBuilder let routeDestination: (TasksRoute) -> RouteDestination

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedWorklist: TasksWorklistKind = .tasks
    @State private var sidebarPresented = false
    /// Horizontal follow during interactive dismiss (compact slide-over only).
    @State private var sidebarInteractiveOffset: CGFloat = 0
    /// Prefer vertical scrolling in the sidebar until a clear horizontal intent.
    @State private var sidebarDragAxisLocked: Bool?
    @State private var actionTask: TaskItem?

    private var usesPersistentSidebar: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if usesPersistentSidebar {
                NavigationSplitView {
                    sidebar
                        .navigationSplitViewColumnWidth(min: 260, ideal: 286, max: 360)
                } detail: {
                    NavigationStack {
                        worklist
                            .navigationDestination(for: TasksRoute.self, destination: routeDestination)
                    }
                }
            } else {
                NavigationStack {
                    ZStack(alignment: .leading) {
                        worklist
                            .accessibilityHidden(sidebarPresented)

                        if compactSidebarIsMounted {
                            Color.black.opacity(compactSidebarScrimOpacity)
                                .ignoresSafeArea()
                                .onTapGesture { closeSidebar() }
                                .allowsHitTesting(sidebarPresented)

                            sidebar
                                .frame(width: compactSidebarWidth)
                                .offset(x: compactSidebarOffsetX)
                                .simultaneousGesture(compactSidebarSwipeToDismissGesture)
                        }
                    }
                    .navigationDestination(for: TasksRoute.self, destination: routeDestination)
                }
            }
        }
        .onChange(of: sidebarPresented) { _, isOpen in
            if isOpen {
                sidebarInteractiveOffset = 0
                sidebarDragAxisLocked = nil
            }
        }
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
        Group {
            if selectedWorklist == .notionProjects {
                notionProjectsWorklist
            } else if selectedWorklist == .linearProjects {
                linearProjectsWorklist
            } else {
                taskScrollWorklist
            }
        }
        .background(CueInColors.background.ignoresSafeArea())
        .navigationTitle(selectedTitle)
        .cueInNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !usesPersistentSidebar {
                TasksWorklistChromeToolbar(
                    sidebarPresented: $sidebarPresented,
                    onOpenSettings: onOpenSettings
                )
            }
        }
    }

    var taskScrollWorklist: some View {
        let tasks = visibleTasks
        return ScrollView(.vertical, showsIndicators: false) {
            if tasks.isEmpty {
                TaskEmptyPanel(
                    icon: selectedEmptyIcon,
                    title: selectedEmptyTitle,
                    actionTitle: selectedWorklist == .notionTasks ? "Sync Notion" : (selectedWorklist == .linearTasks ? "Sync Linear" : "New task"),
                    action: {
                        if selectedWorklist == .notionTasks || selectedWorklist == .linearTasks {
                            onOpenSettings()
                        } else {
                            onCreateTask(defaultsForCreate)
                        }
                    }
                )
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.top, CueInSpacing.xl)
            } else {
                ReorderableTaskList(
                    tasks: tasks,
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
    }

    var notionProjectsWorklist: some View {
        let projects = store.projects.filter(\.isNotionImported)
        return ScrollView(.vertical, showsIndicators: false) {
            if projects.isEmpty {
                TaskEmptyPanel(
                    icon: "folder",
                    title: "No Notion projects",
                    actionTitle: "Open settings",
                    action: onOpenSettings
                )
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.top, CueInSpacing.xl)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: CueInSpacing.md),
                        GridItem(.flexible(), spacing: CueInSpacing.md),
                    ],
                    spacing: CueInSpacing.md
                ) {
                    ForEach(projects) { project in
                        NavigationLink(value: TasksRoute.project(project.id)) {
                            ProjectDashboardCard(project: project, store: store)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.top, CueInSpacing.md)
                .padding(.bottom, CueInLayout.scrollBottomInset)
            }
        }
    }

    var linearProjectsWorklist: some View {
        let projects = store.projects.filter(\.isLinearImported)
        return ScrollView(.vertical, showsIndicators: false) {
            if projects.isEmpty {
                TaskEmptyPanel(
                    icon: "folder",
                    title: "No Linear projects",
                    actionTitle: "Open settings",
                    action: onOpenSettings
                )
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.top, CueInSpacing.xl)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: CueInSpacing.md),
                        GridItem(.flexible(), spacing: CueInSpacing.md),
                    ],
                    spacing: CueInSpacing.md
                ) {
                    ForEach(projects) { project in
                        NavigationLink(value: TasksRoute.project(project.id)) {
                            ProjectDashboardCard(project: project, store: store)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.top, CueInSpacing.md)
                .padding(.bottom, CueInLayout.scrollBottomInset)
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
            showsTrailingHairline: !usesPersistentSidebar,
            showsHeaderDisplayPreferencesMenu: usesPersistentSidebar,
            onOpenSettings: onOpenSettings
        )
    }

    var compactSidebarIsMounted: Bool {
        sidebarPresented || sidebarInteractiveOffset != 0
    }

    func closeSidebar() {
        guard !usesPersistentSidebar else {
            sidebarPresented = false
            return
        }
        finishCompactSidebarInteractiveDismiss()
    }

    var compactSidebarWidth: CGFloat {
        #if os(macOS)
        min(340, (NSScreen.main?.frame.width ?? 1200) * 0.36)
        #else
        min(340, UIScreen.main.bounds.width * 0.86)
        #endif
    }

    var compactSidebarOffsetX: CGFloat {
        if sidebarPresented {
            return sidebarInteractiveOffset
        }
        return -compactSidebarWidth
    }

    var compactSidebarScrimOpacity: CGFloat {
        guard sidebarPresented else { return 0 }
        let w = compactSidebarWidth
        guard w > 0 else { return 0 }
        let t = sidebarInteractiveOffset
        return 0.3 * (1 + t / w)
    }

    var compactSidebarSwipeToDismissGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard sidebarPresented else { return }
                let dx = value.translation.width
                let dy = value.translation.height

                if sidebarDragAxisLocked == nil {
                    let adx = abs(dx)
                    let ady = abs(dy)
                    if adx > 14, adx > ady * 1.25 {
                        sidebarDragAxisLocked = true
                    } else if ady > 14, ady > adx * 1.25 {
                        sidebarDragAxisLocked = false
                    }
                }

                guard sidebarDragAxisLocked == true else { return }

                let w = compactSidebarWidth
                sidebarInteractiveOffset = min(0, max(-w, dx))
            }
            .onEnded { value in
                defer {
                    sidebarDragAxisLocked = nil
                }
                guard sidebarPresented else { return }

                let w = compactSidebarWidth
                let dx = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let shouldClose = sidebarDragAxisLocked == true
                    && (dx < -w * 0.2 || predicted < -w * 0.45)

                if shouldClose {
                    finishCompactSidebarInteractiveDismiss()
                } else {
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                        sidebarInteractiveOffset = 0
                    }
                }
            }
    }

    /// Animate panel fully off-screen, then clear presented state (avoids offset snap).
    func finishCompactSidebarInteractiveDismiss() {
        let w = compactSidebarWidth
        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
            sidebarInteractiveOffset = -w
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            sidebarPresented = false
            sidebarInteractiveOffset = 0
        }
    }

}

private extension TasksHomeView {
    func cueInListFilter(_ task: TaskItem) -> Bool {
        TasksModulePreferences.shouldShowTaskInCueInLists(task)
    }

    var visibleTasks: [TaskItem] {
        switch selectedWorklist {
        case .tasks:
            return tasksList
        case .collection(.today):
            return store.todayTasks.filter { !$0.isCompleted && cueInListFilter($0) }
        case .collection(.inbox):
            return store.inboxTasks.filter(cueInListFilter)
        case .collection(.upcoming):
            return store.upcomingTasks.filter(cueInListFilter)
        case .collection(.all):
            return store.tasks.filter { $0.status != .archived && cueInListFilter($0) }
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
        case .notionTasks:
            return store.tasks
                .filter { store.isNotionTask($0) && $0.status != .archived }
                .sorted(by: actionSort)
        case .notionProjects:
            return []
        case .linearTasks:
            return store.tasks
                .filter { store.isLinearTask($0) && $0.status != .archived }
                .sorted(by: actionSort)
        case .linearProjects:
            return []
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
        store.activeTasks.filter(cueInListFilter).sorted(by: actionSort)
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
        case .notionTasks: return "tasks-worklist:notion"
        case .notionProjects: return "tasks-worklist:notion-projects"
        case .linearTasks: return "tasks-worklist:linear"
        case .linearProjects: return "tasks-worklist:linear-projects"
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
        case .notionTasks: return "Notion tasks"
        case .notionProjects: return "Notion projects"
        case .linearTasks: return "Linear tasks"
        case .linearProjects: return "Linear projects"
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
        case .notionTasks: return "doc.text.fill"
        case .notionProjects: return "folder.fill"
        case .linearTasks: return "doc.text.fill"
        case .linearProjects: return "folder.fill"
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
        case .notionTasks: return "No Notion tasks yet"
        case .notionProjects: return "No Notion projects"
        case .linearTasks: return "No Linear tasks yet"
        case .linearProjects: return "No Linear projects"
        case .field: return "No active tasks"
        case .project: return "No project tasks"
        }
    }
}

// MARK: - Tasks worklist toolbar (compact: glass sidebar + glass overflow, separate items)

private struct CueInToolbarIconPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct TasksWorklistChromeToolbar: ToolbarContent {
    @Binding var sidebarPresented: Bool
    let onOpenSettings: () -> Void

    var body: some ToolbarContent {
        chromeItems
            .cueInHideSharedToolbarGlassBackground()
    }

    @ToolbarContentBuilder
    private var chromeItems: some ToolbarContent {
        ToolbarItem(placement: CueInToolbarPlacement.topBarLeading) {
            Button {
                withAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
                    sidebarPresented.toggle()
                }
            } label: {
                Image(systemName: sidebarPresented ? "xmark" : "sidebar.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CueInColors.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .modifier(CueInStableGlassCircleModifier())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(CueInToolbarIconPressStyle())
            .fixedSize(horizontal: true, vertical: true)
            .accessibilityLabel(sidebarPresented ? "Close library" : "Open task library")
        }
        if sidebarPresented {
            ToolbarItem(placement: CueInToolbarPlacement.topBarLeading) {
                Menu {
                    TasksSidebarOverflowMenuContent(onOpenSettings: onOpenSettings)
                } label: {
                    // Extra layout margin so the 44pt glass circle is not clipped by the
                    // nav toolbar host during the moment `sidebarPresented` flips off.
                    CueInOverflowMenuGlyph()
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .compositingGroup()
                .fixedSize(horizontal: true, vertical: true)
                .accessibilityLabel("Tasks menu")
            }
        }
    }
}

// MARK: - Sidebar overflow (settings + quick display)

private struct TasksSidebarOverflowMenuContent: View {
    let onOpenSettings: () -> Void

    var body: some View {
        Button {
            onOpenSettings()
        } label: {
            Label("Settings", systemImage: "gearshape")
        }

        Divider()

        TasksTaskDisplayPreferencesMenuContent()
    }
}

// MARK: - Task list display preferences (shared by sidebar + compact toolbar)

private struct TasksTaskDisplayPreferencesMenuContent: View {
    @AppStorage(TasksTaskDisplayPrefs.densityKey) private var densityRaw = TasksDisplayDensity.compact.rawValue
    @AppStorage(TasksTaskDisplayPrefs.metadataKey) private var metadataRaw = TasksMetadataLevel.balanced.rawValue
    @AppStorage(TasksTaskDisplayPrefs.showProjectKey) private var showProject = true
    @AppStorage(TasksTaskDisplayPrefs.showDueKey) private var showDue = true
    @AppStorage(TasksTaskDisplayPrefs.showEstimateKey) private var showEstimate = true
    @AppStorage(TasksTaskDisplayPrefs.showPriorityKey) private var showPriority = true

    var body: some View {
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
}

private struct TasksLinearSidebar: View {
    let store: TasksStore
    let selectedWorklist: TasksWorklistKind
    let onSelectWorklist: (TasksWorklistKind) -> Void
    let onCreateField: () -> Void
    let onCreateProject: (UUID?) -> Void
    let showsTrailingHairline: Bool
    /// Split layout: overflow menu in sidebar header. Compact: menu is separate leading toolbar item when drawer is open.
    let showsHeaderDisplayPreferencesMenu: Bool
    let onOpenSettings: () -> Void
    @Bindable private var notionStore = NotionIntegrationStore.shared
    @Bindable private var linearStore = LinearIntegrationStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            sidebarHeader

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: CueInSpacing.base) {
                    sidebarSection("Tasks") {
                        sidebarRow(.tasks, title: "Tasks", icon: "checklist", count: tasksCount)
                        sidebarRow(.collection(.today), title: "To-do", icon: "circle.grid.2x2", count: store.todayTasks.filter { !$0.isCompleted && TasksModulePreferences.shouldShowTaskInCueInLists($0) }.count)
                        sidebarRow(.collection(.inbox), title: "Inbox", icon: "tray", count: store.inboxTasks.filter { TasksModulePreferences.shouldShowTaskInCueInLists($0) }.count)
                        sidebarRow(.collection(.upcoming), title: "Upcoming", icon: "calendar", count: store.upcomingTasks.filter { TasksModulePreferences.shouldShowTaskInCueInLists($0) }.count)
                    }

                    sidebarSection("Plan") {
                        sidebarRouteRow(title: "Projects", icon: "folder", route: .projects(nil), count: cueInProjectCount)
                        sidebarRouteRow(title: "Fields", icon: "square.grid.2x2", route: .initiatives, count: store.fields.count)
                    }

                    sidebarSection("Notion") {
                        sidebarRow(.notionTasks, title: "Tasks", icon: "doc.text.fill", count: notionTaskCount, tint: notionAccent)
                        sidebarRow(.notionProjects, title: "Projects", icon: "folder.fill", count: notionProjectCount, tint: notionAccent)

                        if notionIsConnected, let workspaceTitle {
                            sidebarStaticRow(title: workspaceTitle, icon: "building.2", count: nil, tint: CueInColors.textTertiary)
                        } else if !notionIsConnected {
                            Button {
                                onOpenSettings()
                            } label: {
                                sidebarRowContent(
                                    title: "Connect Notion",
                                    icon: "link",
                                    count: nil,
                                    isSelected: false,
                                    tint: CueInColors.accentFocus
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    sidebarSection("Linear") {
                        sidebarRow(.linearTasks, title: "Tasks", icon: "doc.text.fill", count: linearTaskCount, tint: linearAccent)
                        sidebarRow(.linearProjects, title: "Projects", icon: "folder.fill", count: linearProjectCount, tint: linearAccent)

                        if linearIsConnected, let linearWorkspaceTitle {
                            sidebarStaticRow(title: linearWorkspaceTitle, icon: "building.2", count: nil, tint: CueInColors.textTertiary)
                        } else if !linearIsConnected {
                            Button {
                                onOpenSettings()
                            } label: {
                                sidebarRowContent(
                                    title: "Connect Linear",
                                    icon: "link",
                                    count: nil,
                                    isSelected: false,
                                    tint: CueInColors.accentFocus
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    sidebarSection("Rhythm") {
                        sidebarRow(.habits, title: "Habits", icon: "repeat", count: habitsCount)
                        sidebarRow(.rituals, title: "Rituals", icon: "sparkles", count: ritualsCount)
                    }

                    sidebarSection("Library") {
                        sidebarRow(.saved, title: "Saved", icon: "bookmark", count: store.tasks.filter(\.savesToArchive).count)
                        sidebarRow(.archived, title: "Archive", icon: "archivebox", count: store.tasks.filter { $0.status == .archived }.count)
                        sidebarRow(.completed, title: "Completed", icon: "checkmark.circle", count: store.tasks.filter(\.isCompleted).count)
                        sidebarRow(.collection(.all), title: "All", icon: "list.bullet", count: store.tasks.filter { $0.status != .archived && TasksModulePreferences.shouldShowTaskInCueInLists($0) }.count)
                    }
                }
                .padding(.horizontal, CueInSpacing.md)
                .padding(.bottom, CueInLayout.scrollBottomInset)
            }
        }
        .padding(.top, CueInSpacing.xs)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(CueInColors.surfacePrimary.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            if showsTrailingHairline {
                Rectangle()
                    .fill(CueInColors.divider.opacity(0.75))
                    .frame(width: 1)
                    .ignoresSafeArea(edges: .vertical)
            }
        }
    }

    @ViewBuilder
    private var sidebarHeader: some View {
        if showsHeaderDisplayPreferencesMenu {
            HStack(alignment: .center, spacing: CueInSpacing.sm) {
                Spacer(minLength: 0)
                Menu {
                    TasksSidebarOverflowMenuContent(onOpenSettings: onOpenSettings)
                } label: {
                    CueInOverflowMenuGlyph()
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: true)
                .compositingGroup()
                .accessibilityLabel("Tasks menu")
            }
            .padding(.horizontal, CueInSpacing.md)
            .padding(.vertical, 2)
        }
    }

    private var notionAccent: Color {
        CueInColors.accentRoutine
    }

    private var linearAccent: Color {
        CueInColors.accentMini
    }

    private var tasksCount: Int {
        store.activeTasks.filter { TasksModulePreferences.shouldShowTaskInCueInLists($0) }.count
    }

    private var cueInProjectCount: Int {
        store.projects.filter { !$0.isExternal }.count
    }

    private var habitsCount: Int {
        store.activeTasks.filter { $0.tags.contains("habit") || $0.recurrence != .none }.count
    }

    private var ritualsCount: Int {
        store.activeTasks.filter { $0.tags.contains("ritual") || $0.tags.contains("routine") }.count
    }

    private var notionTaskCount: Int {
        store.tasks.filter { store.isNotionTask($0) && $0.status != .archived }.count
    }

    private var notionProjectCount: Int {
        store.projects.filter(\.isNotionImported).count
    }

    private var notionIsConnected: Bool {
        if case .connected = notionStore.state { return true }
        return false
    }

    private var workspaceTitle: String? {
        if case let .connected(connection) = notionStore.state {
            return connection.workspaceName ?? "Notion workspace"
        }
        return nil
    }

    private var linearTaskCount: Int {
        store.tasks.filter { store.isLinearTask($0) && $0.status != .archived }.count
    }

    private var linearProjectCount: Int {
        store.projects.filter(\.isLinearImported).count
    }

    private var linearIsConnected: Bool {
        if case .connected = linearStore.state { return true }
        return false
    }

    private var linearWorkspaceTitle: String? {
        if case let .connected(connection) = linearStore.state {
            return connection.workspaceName ?? "Linear workspace"
        }
        return nil
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

    private func sidebarStaticRow(title: String, icon: String, count: Int?, tint: Color) -> some View {
        sidebarRowContent(
            title: title,
            icon: icon,
            count: count,
            isSelected: false,
            tint: tint
        )
        .accessibilityElement(children: .combine)
    }

    private func sidebarRowContent(
        title: String,
        icon: String,
        count: Int?,
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

            if let count {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CueInColors.textTertiary)
                    .monospacedDigit()
            }
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
