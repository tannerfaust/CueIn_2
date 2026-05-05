import SwiftUI

struct TasksHomeView: View {
    let store: TasksStore
    let onCreateTask: (TaskDraftDefaults) -> Void
    let onOpenTask: (UUID) -> Void
    let onOpenSearch: () -> Void
    let onCreateField: () -> Void
    let onCreateProject: (UUID?) -> Void
    let onPoolMove: (TaskItem, Bool) -> Void
    let onDeleteTask: (TaskItem, String) -> Void

    private var openTasks: [TaskItem] {
        store.tasks.filter { !$0.isCompleted && $0.status != .archived }
    }

    private var todayOpenTasks: [TaskItem] {
        store.todayTasks.filter { !$0.isCompleted }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: CueInSpacing.xl) {
                TasksHomeHeader(
                    openCount: openTasks.count,
                    completedTodayCount: store.completedTodayTasks.count,
                    onSearch: onOpenSearch,
                    onNewTask: { onCreateTask(.today()) },
                    onNewInboxTask: { onCreateTask(.inbox) },
                    onNewProject: { onCreateProject(nil) },
                    onNewField: onCreateField
                )

                TasksSignalStrip(store: store)

                TodayFocusSection(
                    store: store,
                    tasks: todayOpenTasks,
                    onOpenTask: onOpenTask,
                    onCreateTask: { onCreateTask(.today()) },
                    onPoolMove: onPoolMove,
                    onDeleteTask: onDeleteTask
                )

                TaskRouteGrid(store: store)

                WorkMapSection(
                    store: store,
                    onCreateField: onCreateField,
                    onCreateProject: onCreateProject
                )
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)
            .padding(.top, 14)
            .padding(.bottom, CueInLayout.scrollBottomInset)
        }
        .overlay(alignment: .top) {
            CueInColors.background
                .frame(height: 70)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }
}

private struct TasksHomeHeader: View {
    let openCount: Int
    let completedTodayCount: Int
    let onSearch: () -> Void
    let onNewTask: () -> Void
    let onNewInboxTask: () -> Void
    let onNewProject: () -> Void
    let onNewField: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack(alignment: .center, spacing: CueInSpacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tasks")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(CueInColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text("\(openCount) open")
                        Text("·")
                        Text("\(completedTodayCount) done today")
                    }
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .monospacedDigit()
                }

                Spacer(minLength: CueInSpacing.md)

                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CueInColors.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .modifier(CueInStableGlassCircleModifier())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search tasks")

                Menu {
                    Button(action: onNewTask) {
                        Label("New task", systemImage: "checklist")
                    }
                    Button(action: onNewInboxTask) {
                        Label("New inbox task", systemImage: "tray")
                    }
                    Button(action: onNewProject) {
                        Label("New project", systemImage: "folder.badge.plus")
                    }
                    Button(action: onNewField) {
                        Label("New initiative", systemImage: "square.grid.2x2")
                    }
                } label: {
                    CueInOverflowMenuGlyph()
                }
            }
        }
    }
}

private struct TasksSignalStrip: View {
    let store: TasksStore

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: CueInSpacing.sm),
                GridItem(.flexible(), spacing: CueInSpacing.sm),
                GridItem(.flexible(), spacing: CueInSpacing.sm),
                GridItem(.flexible(), spacing: CueInSpacing.sm)
            ],
            spacing: CueInSpacing.sm
        ) {
            SignalTile(
                title: "Today",
                value: store.todayTasks.filter { !$0.isCompleted }.count,
                icon: "sun.max.fill",
                tint: CueInColors.accentFixed,
                route: .collection(.today)
            )
            SignalTile(
                title: "Inbox",
                value: store.inboxTasks.count,
                icon: "tray.fill",
                tint: CueInColors.textSecondary,
                route: .collection(.inbox)
            )
            SignalTile(
                title: "Overdue",
                value: store.overdueTasks.count,
                icon: "exclamationmark.circle.fill",
                tint: CueInColors.danger,
                route: .priority
            )
            SignalTile(
                title: "Projects",
                value: store.projects.filter { $0.status == .active }.count,
                icon: "folder.fill",
                tint: CueInColors.accentFocus,
                route: .projects
            )
        }
    }
}

private struct SignalTile: View {
    let title: String
    let value: Int
    let icon: String
    let tint: Color
    let route: TasksRoute

    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)

                Text("\(value)")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(CueInColors.textPrimary)
                    .monospacedDigit()

                Text(title)
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .padding(CueInSpacing.md)
            .background(CueInColors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(tint.opacity(0.16), lineWidth: 0.6)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct TodayFocusSection: View {
    let store: TasksStore
    let tasks: [TaskItem]
    let onOpenTask: (UUID) -> Void
    let onCreateTask: () -> Void
    let onPoolMove: (TaskItem, Bool) -> Void
    let onDeleteTask: (TaskItem, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            TaskSectionHeader(
                title: "Today",
                icon: "bolt.fill",
                tint: CueInColors.accentFixed,
                trailing: AnyView(todayTrailing)
            )

            if tasks.isEmpty {
                TaskEmptyPanel(
                    icon: "sun.max",
                    title: "Today is clear",
                    actionTitle: "New task",
                    action: onCreateTask
                )
            } else {
                VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                    ReorderableTaskList(
                        tasks: Array(tasks.prefix(5)),
                        listKey: "tasks-home:today",
                        onOpenTask: onOpenTask,
                        onPoolMove: onPoolMove,
                        onDeleteTask: onDeleteTask
                    )

                    NavigationLink(value: TasksRoute.collection(.today)) {
                        HStack(spacing: 6) {
                            Text("Open Today")
                                .font(CueInTypography.captionMedium)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(CueInColors.accentFixed)
                        .padding(.top, 2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(CueInSpacing.md)
                .background(CueInColors.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                        .strokeBorder(CueInColors.cardBorder, lineWidth: 0.6)
                }
            }
        }
    }

    private var todayTrailing: some View {
        Button(action: onCreateTask) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CueInColors.textPrimary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New task")
    }
}

private struct TaskRouteGrid: View {
    let store: TasksStore

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            TaskSectionHeader(
                title: "Views",
                icon: "rectangle.grid.2x2.fill",
                tint: CueInColors.accentRoutine
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: CueInSpacing.md),
                    GridItem(.flexible(), spacing: CueInSpacing.md)
                ],
                spacing: CueInSpacing.md
            ) {
                ForEach(TaskCollectionKind.allCases) { kind in
                    TaskViewCard(
                        title: kind.title,
                        value: count(for: kind),
                        icon: kind.icon,
                        tint: kind.tint,
                        route: .collection(kind)
                    )
                }

                TaskViewCard(
                    title: "Priority",
                    value: priorityCount,
                    icon: "flame.fill",
                    tint: CueInColors.danger,
                    route: .priority
                )

                TaskViewCard(
                    title: "Projects",
                    value: store.projects.count,
                    icon: "folder.fill",
                    tint: CueInColors.accentFocus,
                    route: .projects
                )
            }
        }
    }

    private func count(for kind: TaskCollectionKind) -> Int {
        switch kind {
        case .today: return store.todayTasks.filter { !$0.isCompleted }.count
        case .inbox: return store.inboxTasks.count
        case .upcoming: return store.upcomingTasks.count
        case .all: return store.tasks.filter { $0.status != .archived }.count
        }
    }

    private var priorityCount: Int {
        store.activeTasks.filter { $0.priority != .normal || $0.isOverdue }.count
    }
}

private struct TaskViewCard: View {
    let title: String
    let value: Int
    let icon: String
    let tint: Color
    let route: TasksRoute

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: CueInSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint.opacity(0.14))
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)

                    Text("\(value)")
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                        .monospacedDigit()
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CueInColors.textTertiary)
            }
            .padding(CueInSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .background(CueInColors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(CueInColors.cardBorder, lineWidth: 0.6)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct WorkMapSection: View {
    let store: TasksStore
    let onCreateField: () -> Void
    let onCreateProject: (UUID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            TaskSectionHeader(
                title: "Work Map",
                icon: "map.fill",
                tint: CueInColors.accentMini,
                trailing: AnyView(workMapActions)
            )

            NavigationLink(value: TasksRoute.initiatives) {
                HStack(spacing: CueInSpacing.md) {
                    WorkMapIcon(
                        icon: "square.grid.2x2.fill",
                        tint: CueInColors.accentMini
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Initiatives")
                            .font(CueInTypography.bodyMedium)
                            .foregroundStyle(CueInColors.textPrimary)
                        Text("\(store.fields.count) areas · \(store.projects.count) projects")
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textTertiary)
                            .monospacedDigit()
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CueInColors.textTertiary)
                }
                .padding(CueInSpacing.md)
                .background(CueInColors.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                        .strokeBorder(CueInColors.cardBorder, lineWidth: 0.6)
                }
            }
            .buttonStyle(.plain)

            VStack(spacing: 0) {
                ForEach(Array(store.projects.prefix(4).enumerated()), id: \.element.id) { index, project in
                    NavigationLink(value: TasksRoute.project(project.id)) {
                        ProjectRow(project: project, store: store)
                    }
                    .buttonStyle(.plain)

                    if index < min(store.projects.count, 4) - 1 {
                        Divider()
                            .background(CueInColors.divider)
                            .padding(.leading, CueInSpacing.screenHorizontal + 38)
                    }
                }
            }
            .background(CueInColors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                    .strokeBorder(CueInColors.cardBorder, lineWidth: 0.6)
            }

            NavigationLink(value: TasksRoute.projects) {
                HStack(spacing: 6) {
                    Text("Open Projects")
                        .font(CueInTypography.captionMedium)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(CueInColors.accentFocus)
            }
            .buttonStyle(.plain)
        }
    }

    private var workMapActions: some View {
        Menu {
            Button(action: onCreateField) {
                Label("New initiative", systemImage: "square.grid.2x2")
            }
            Button { onCreateProject(nil) } label: {
                Label("New project", systemImage: "folder.badge.plus")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CueInColors.textPrimary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
    }
}

private struct WorkMapIcon: View {
    let icon: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint.opacity(0.14))
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 38, height: 38)
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
                .foregroundStyle(tint)
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
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(CueInColors.textTertiary)
            Text(title)
                .font(CueInTypography.captionMedium)
                .foregroundStyle(CueInColors.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(CueInColors.accentFocus)
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
