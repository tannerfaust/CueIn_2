import SwiftUI

struct TaskPriorityMatrixPage: View {
    let store: TasksStore
    let onOpenTask: (UUID) -> Void
    let onCreateTask: (TaskDraftDefaults) -> Void

    private var activeTasks: [TaskItem] {
        store.activeTasks
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: CueInSpacing.xl) {
                PlanningPageHeader(
                    title: "Priority",
                    subtitle: "\(priorityCount) pressure items",
                    icon: "flame.fill",
                    tint: CueInColors.danger
                ) {
                    onCreateTask(TaskDraftDefaults(priority: .high))
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: CueInSpacing.md),
                        GridItem(.flexible(), spacing: CueInSpacing.md)
                    ],
                    spacing: CueInSpacing.md
                ) {
                    PriorityQuadrantCard(
                        title: "Now",
                        subtitle: "urgent + high",
                        icon: "exclamationmark.triangle.fill",
                        tint: CueInColors.danger,
                        tasks: nowTasks,
                        store: store,
                        onOpenTask: onOpenTask
                    )

                    PriorityQuadrantCard(
                        title: "Focus",
                        subtitle: "high priority",
                        icon: "scope",
                        tint: CueInColors.accentFocus,
                        tasks: focusTasks,
                        store: store,
                        onOpenTask: onOpenTask
                    )

                    PriorityQuadrantCard(
                        title: "Soon",
                        subtitle: "date pressure",
                        icon: "calendar.badge.clock",
                        tint: CueInColors.accentFixed,
                        tasks: soonTasks,
                        store: store,
                        onOpenTask: onOpenTask
                    )

                    PriorityQuadrantCard(
                        title: "Later",
                        subtitle: "low pressure",
                        icon: "tray.full.fill",
                        tint: CueInColors.textSecondary,
                        tasks: laterTasks,
                        store: store,
                        onOpenTask: onOpenTask
                    )
                }
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)
            .padding(.top, CueInSpacing.base)
            .padding(.bottom, CueInLayout.scrollBottomInset)
        }
        .background(CueInColors.background.ignoresSafeArea())
        .navigationTitle("Priority")
        .cueInNavigationBarTitleDisplayMode(.inline)
    }
}

private extension TaskPriorityMatrixPage {
    var priorityCount: Int {
        activeTasks.filter { $0.priority != .normal || $0.isOverdue || isDueSoon($0) }.count
    }

    var nowTasks: [TaskItem] {
        sort(
            activeTasks.filter {
                ($0.priority == .urgent || $0.priority == .high) && ($0.isOverdue || isDueToday($0))
            }
        )
    }

    var focusTasks: [TaskItem] {
        sort(
            activeTasks.filter {
                ($0.priority == .urgent || $0.priority == .high) && !nowTasks.map(\.id).contains($0.id)
            }
        )
    }

    var soonTasks: [TaskItem] {
        let used = Set(nowTasks.map(\.id) + focusTasks.map(\.id))
        return sort(
            activeTasks.filter {
                !used.contains($0.id) && ($0.isOverdue || isDueToday($0) || isDueSoon($0))
            }
        )
    }

    var laterTasks: [TaskItem] {
        let used = Set(nowTasks.map(\.id) + focusTasks.map(\.id) + soonTasks.map(\.id))
        return sort(activeTasks.filter { !used.contains($0.id) })
    }

    func isDueToday(_ task: TaskItem) -> Bool {
        guard let due = task.dueDate else { return false }
        return Calendar.current.isDateInToday(due)
    }

    func isDueSoon(_ task: TaskItem) -> Bool {
        guard let due = task.dueDate else { return false }
        let today = Calendar.current.startOfDay(for: Date())
        let soon = Calendar.current.date(byAdding: .day, value: 3, to: today) ?? today
        return due >= today && due <= soon
    }

    func sort(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted {
            if $0.priority.sortWeight != $1.priority.sortWeight {
                return $0.priority.sortWeight < $1.priority.sortWeight
            }
            return ($0.dueDate ?? $0.scheduledDate ?? .distantFuture)
                < ($1.dueDate ?? $1.scheduledDate ?? .distantFuture)
        }
    }
}

private struct PriorityQuadrantCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let tasks: [TaskItem]
    let store: TasksStore
    let onOpenTask: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack(spacing: CueInSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.14))
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                    Text(subtitle)
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 4)

                Text("\(tasks.count)")
                    .font(CueInTypography.micro)
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }

            if tasks.isEmpty {
                Text("Clear")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .center)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(tasks.prefix(4).enumerated()), id: \.element.id) { index, task in
                        Button {
                            onOpenTask(task.id)
                        } label: {
                            PriorityTaskLine(task: task, store: store, tint: tint)
                        }
                        .buttonStyle(.plain)

                        if index < min(tasks.count, 4) - 1 {
                            Divider()
                                .background(CueInColors.divider)
                        }
                    }
                }
            }
        }
        .padding(CueInSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 186, alignment: .topLeading)
        .background(CueInColors.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 0.6)
        }
    }
}

private struct PriorityTaskLine: View {
    let task: TaskItem
    let store: TasksStore
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(task.title)
                .font(CueInTypography.captionMedium)
                .foregroundStyle(CueInColors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                if let project = store.project(task.projectID) {
                    Text(project.name)
                        .lineLimit(1)
                } else if let field = store.field(task.fieldID) {
                    Text(field.name)
                        .lineLimit(1)
                }

                if task.priority != .normal {
                    Image(systemName: task.priority.icon)
                }

                if let due = task.dueDate {
                    Text(dueLabel(due))
                }
            }
            .font(CueInTypography.micro)
            .foregroundStyle(CueInColors.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func dueLabel(_ date: Date) -> String {
        if task.isOverdue { return "Overdue" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct TaskInitiativesPage: View {
    let store: TasksStore
    let onCreateField: () -> Void
    let onEditField: (UUID) -> Void
    let onDeleteField: (UUID) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: CueInSpacing.xl) {
                PlanningPageHeader(
                    title: "Fields",
                    subtitle: "\(store.fields.count) areas",
                    icon: "square.grid.2x2",
                    tint: CueInColors.textTertiary,
                    onCreate: onCreateField
                )

                LazyVStack(spacing: CueInSpacing.md) {
                    ForEach(store.fields) { field in
                        NavigationLink(value: TasksRoute.field(field.id)) {
                            InitiativeListCard(field: field, store: store)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                onEditField(field.id)
                            } label: {
                                Label("Edit initiative", systemImage: "pencil")
                            }

                            Button {
                                onCreateField()
                            } label: {
                                Label("New initiative", systemImage: "plus")
                            }

                            Divider()

                            Button(role: .destructive) {
                                onDeleteField(field.id)
                            } label: {
                                Label("Delete initiative", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)
            .padding(.top, CueInSpacing.base)
            .padding(.bottom, CueInLayout.scrollBottomInset)
        }
        .background(CueInColors.background.ignoresSafeArea())
        .navigationTitle("Fields")
        .cueInNavigationBarTitleDisplayMode(.inline)
    }
}

private struct InitiativeListCard: View {
    let field: Field
    let store: TasksStore

    private var stats: (done: Int, total: Int) {
        store.progress(field: field)
    }

    private var progress: Double {
        stats.total > 0 ? Double(stats.done) / Double(stats.total) : 0
    }

    private var projects: [Project] {
        store.projects(in: field.id)
    }

    private var openCount: Int {
        store.tasks(in: field.id).filter { !$0.isCompleted && $0.status != .archived }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: CueInSpacing.sm) {
                Circle()
                    .fill(field.color.opacity(0.75))
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 3) {
                    Text(field.name)
                        .font(CueInTypography.headline)
                        .foregroundStyle(CueInColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text("\(openCount) open")
                        Text("·")
                        Text("\(projects.count) projects")
                    }
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
                    .monospacedDigit()
                }

                Spacer(minLength: CueInSpacing.sm)

                Text("\(Int(progress * 100))%")
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CueInColors.surfaceTertiary)
                    Capsule()
                        .fill(CueInColors.textTertiary.opacity(0.7))
                        .frame(width: geo.size.width * progress)
                        .animation(.easeInOut(duration: 0.35), value: progress)
                }
            }
            .frame(height: 4)

            if !projects.isEmpty {
                HStack(spacing: CueInSpacing.sm) {
                    ForEach(projects.prefix(3)) { project in
                        Text(project.name)
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(CueInColors.surfaceSecondary.opacity(0.75))
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(CueInSpacing.base)
        .background(CueInColors.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                .strokeBorder(CueInColors.cardBorder, lineWidth: 0.6)
        }
    }
}

struct TaskProjectsPage: View {
    let store: TasksStore
    let onCreateProject: (UUID?) -> Void
    let onEditProject: (UUID) -> Void
    let onDeleteProject: (UUID) -> Void
    @State private var sourceFilter: ProjectSourceFilter = .all

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: CueInSpacing.xl) {
                HStack(alignment: .center, spacing: CueInSpacing.sm) {
                    Image(systemName: "folder")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CueInColors.textTertiary)
                    Text("\(store.projects.count) total")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }

                if hasNotionProjects {
                    Picker("Project source", selection: $sourceFilter) {
                        ForEach(ProjectSourceFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: CueInSpacing.md),
                        GridItem(.flexible(), spacing: CueInSpacing.md)
                    ],
                    spacing: CueInSpacing.md
                ) {
                    ForEach(filteredProjects) { project in
                        NavigationLink(value: TasksRoute.project(project.id)) {
                            ProjectDashboardCard(project: project, store: store)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                onEditProject(project.id)
                            } label: {
                                Label("Edit project", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                onDeleteProject(project.id)
                            } label: {
                                Label("Delete project", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)
            .padding(.top, CueInSpacing.base)
            .padding(.bottom, CueInLayout.scrollBottomInset)
        }
        .background(CueInColors.background.ignoresSafeArea())
        .navigationTitle("Projects")
        .cueInNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: CueInToolbarPlacement.topBarTrailing) {
                Menu {
                    Button {
                        onCreateProject(nil)
                    } label: {
                        Label("New project", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(CueInColors.textPrimary)
                }
                .accessibilityLabel("Projects menu")
            }
        }
    }

    private var filteredProjects: [Project] {
        switch sourceFilter {
        case .all:
            return store.projects
        case .cueIn:
            return store.projects.filter { !$0.isNotionImported }
        case .notion:
            return store.projects.filter(\.isNotionImported)
        }
    }

    private var hasNotionProjects: Bool {
        store.projects.contains(where: \.isNotionImported)
    }
}

private enum ProjectSourceFilter: String, CaseIterable, Identifiable {
    case all
    case cueIn
    case notion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .cueIn: return "CueIn"
        case .notion: return "Notion"
        }
    }
}

private struct ProjectDashboardCard: View {
    let project: Project
    let store: TasksStore

    private var color: Color { store.color(for: project) }
    private var stats: (done: Int, total: Int) { store.progress(project: project) }
    private var openCount: Int {
        store.tasksInProject(project.id).filter { !$0.isCompleted && $0.status != .archived }.count
    }
    private var progress: Double {
        stats.total > 0 ? Double(stats.done) / Double(stats.total) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Circle()
                    .fill(color.opacity(0.75))
                    .frame(width: 7, height: 7)

                Text(project.name)
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Text(project.status.label)
                Text("·")
                Text("\(openCount) open")
                if project.isNotionImported {
                    Text("·")
                    Text("Notion")
                }
            }
            .font(CueInTypography.micro)
            .foregroundStyle(CueInColors.textTertiary)
            .monospacedDigit()

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CueInColors.surfaceTertiary)
                    Capsule()
                        .fill(CueInColors.textTertiary.opacity(0.75))
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 3)

            HStack(spacing: CueInSpacing.sm) {
                Text("\(Int(progress * 100))%")
                    .monospacedDigit()
                if let targetDate = project.targetDate {
                    Text("·")
                    Text(targetDate.formatted(.dateTime.month(.abbreviated).day()))
                        .lineLimit(1)
                }
            }
            .font(CueInTypography.micro)
            .foregroundStyle(CueInColors.textTertiary)
        }
        .padding(CueInSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
        .background(CueInColors.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CueInColors.cardBorder, lineWidth: 0.6)
        }
    }
}

private struct ProjectGroupSection: View {
    let field: Field
    let projects: [Project]
    let store: TasksStore
    let onCreateProject: () -> Void
    let onEditProject: (UUID) -> Void
    let onDeleteProject: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            HStack(spacing: 6) {
                Circle()
                    .fill(field.color.opacity(0.75))
                    .frame(width: 6, height: 6)
                Text(field.name.uppercased())
                    .font(Font.system(size: 10, weight: .semibold))
                    .foregroundStyle(CueInColors.textTertiary)
                Spacer()
                Button(action: onCreateProject) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CueInColors.textSecondary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New project")
            }

            if projects.isEmpty {
                TaskEmptyPanel(
                    icon: "folder",
                    title: "No projects",
                    actionTitle: "New project",
                    action: onCreateProject
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                        NavigationLink(value: TasksRoute.project(project.id)) {
                            ProjectRow(project: project, store: store)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                onEditProject(project.id)
                            } label: {
                                Label("Edit project", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                onDeleteProject(project.id)
                            } label: {
                                Label("Delete project", systemImage: "trash")
                            }
                        }

                        if index < projects.count - 1 {
                            Divider()
                                .background(CueInColors.divider)
                                .padding(.leading, CueInSpacing.screenHorizontal + 38)
                        }
                    }
                }
            }
        }
    }
}

private struct PlanningPageHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let onCreate: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CueInSpacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(CueInColors.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
                    .monospacedDigit()
            }

            Spacer(minLength: CueInSpacing.md)

            Button(action: onCreate) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CueInColors.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
                    .modifier(CueInStableGlassCircleModifier())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create")
        }
    }
}
