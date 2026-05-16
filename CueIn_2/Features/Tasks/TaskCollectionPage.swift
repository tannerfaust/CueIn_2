import SwiftUI

struct TaskCollectionPage: View {
    let kind: TaskCollectionKind
    let store: TasksStore
    let onOpenTask: (UUID) -> Void
    let onCreateTask: (TaskDraftDefaults) -> Void
    let onPoolMove: (TaskItem, Bool) -> Void
    let onDeleteTask: (TaskItem, String) -> Void

    @State private var allScope: AllTasksScope = .open
    @State private var actionTask: TaskItem?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: CueInSpacing.xl) {
                TaskCollectionHeader(
                    kind: kind,
                    openCount: openCount,
                    doneCount: doneCount,
                    onCreate: { onCreateTask(defaultsForCreate) }
                )

                if kind == .all {
                    allScopePicker
                }

                content
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)
            .padding(.top, CueInSpacing.base)
            .padding(.bottom, CueInLayout.scrollBottomInset)
        }
        .background(CueInColors.background.ignoresSafeArea())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
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
                    onDeleteTask(task, kind.listKeyPrefix)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .today:
            todayContent
        case .inbox:
            simpleTaskContent(
                tasks: store.inboxTasks,
                listKey: kind.listKeyPrefix,
                emptyIcon: "tray",
                emptyTitle: "Inbox is clear"
            )
        case .upcoming:
            upcomingContent
        case .all:
            allContent
        }
    }
}

private extension TaskCollectionPage {
    enum AllTasksScope: String, CaseIterable, Identifiable {
        case open = "Open"
        case done = "Done"
        case all = "All"

        var id: String { rawValue }
    }

    var defaultsForCreate: TaskDraftDefaults {
        switch kind {
        case .today: return .today()
        case .inbox: return .inbox
        case .upcoming: return .upcoming()
        case .all: return .inbox
        }
    }

    var baseTasks: [TaskItem] {
        switch kind {
        case .today: return store.todayTasks
        case .inbox: return store.inboxTasks
        case .upcoming: return store.upcomingTasks
        case .all: return store.tasks.filter { $0.status != .archived }
        }
    }

    var openCount: Int {
        baseTasks.filter { !$0.isCompleted }.count
    }

    var doneCount: Int {
        baseTasks.filter(\.isCompleted).count
    }

    var allScopePicker: some View {
        HStack(spacing: CueInSpacing.sm) {
            ForEach(AllTasksScope.allCases) { scope in
                let selected = allScope == scope
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        allScope = scope
                    }
                } label: {
                    Text(scope.rawValue)
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(selected ? CueInColors.textPrimary : CueInColors.textSecondary)
                        .padding(.horizontal, CueInSpacing.md)
                        .padding(.vertical, 7)
                        .background(selected ? CueInColors.surfaceSecondary : Color.clear)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(selected ? Color.clear : CueInColors.divider, lineWidth: 0.6)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    var todayContent: some View {
        let open = store.todayTasks.filter { !$0.isCompleted }
        let done = store.todayTasks.filter(\.isCompleted)

        return VStack(alignment: .leading, spacing: CueInSpacing.xl) {
            if open.isEmpty && done.isEmpty {
                TaskEmptyPanel(
                    icon: "sun.max",
                    title: "To-do is clear",
                    actionTitle: "New task",
                    action: { onCreateTask(.today()) }
                )
            } else {
                if !open.isEmpty {
                    taskStack(
                        tasks: open,
                        listKey: "\(kind.listKeyPrefix):open",
                        sectionTitle: "Execution",
                        sectionSubtitle: "\(open.count)",
                        sectionIcon: "bolt.fill",
                        sectionTint: CueInColors.accentFixed
                    )
                }

                if !done.isEmpty {
                    taskStack(
                        tasks: done,
                        listKey: "\(kind.listKeyPrefix):done",
                        sectionTitle: "Done",
                        sectionSubtitle: "\(done.count)",
                        sectionIcon: "checkmark.circle.fill",
                        sectionTint: CueInColors.success
                    )
                }
            }
        }
    }

    var upcomingContent: some View {
        let grouped = Dictionary(grouping: store.upcomingTasks) { task -> Date in
            Calendar.current.startOfDay(for: task.scheduledDate ?? .distantFuture)
        }
        let days = grouped.keys.sorted()

        return VStack(alignment: .leading, spacing: CueInSpacing.xl) {
            if days.isEmpty {
                TaskEmptyPanel(
                    icon: "calendar",
                    title: "Nothing scheduled",
                    actionTitle: "New task",
                    action: { onCreateTask(.upcoming()) }
                )
            } else {
                ForEach(days, id: \.self) { day in
                    let tasks = grouped[day] ?? []
                    taskStack(
                        tasks: tasks,
                        listKey: store.upcomingListKey(day: day),
                        sectionTitle: day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                        sectionSubtitle: relativeDayLabel(day),
                        sectionIcon: "calendar",
                        sectionTint: CueInColors.accentFocus
                    )
                }
            }
        }
    }

    var allContent: some View {
        let scoped: [TaskItem] = {
            let base = store.tasks.filter { $0.status != .archived }
            switch allScope {
            case .open: return base.filter { !$0.isCompleted }
            case .done: return base.filter(\.isCompleted)
            case .all: return base
            }
        }()

        return VStack(alignment: .leading, spacing: CueInSpacing.xl) {
            if scoped.isEmpty {
                TaskEmptyPanel(icon: "tray", title: "No tasks")
            } else {
                ForEach(groupedByField(scoped), id: \.id) { group in
                    taskStack(
                        tasks: group.tasks,
                        listKey: "\(kind.listKeyPrefix):\(allScope.rawValue):\(group.id)",
                        sectionTitle: group.title,
                        sectionSubtitle: "\(group.tasks.filter(\.isCompleted).count)/\(group.tasks.count)",
                        sectionIcon: group.icon,
                        sectionTint: group.tint
                    )
                }
            }
        }
    }

    func simpleTaskContent(
        tasks: [TaskItem],
        listKey: String,
        emptyIcon: String,
        emptyTitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: CueInSpacing.xl) {
            if tasks.isEmpty {
                TaskEmptyPanel(
                    icon: emptyIcon,
                    title: emptyTitle,
                    actionTitle: "New task",
                    action: { onCreateTask(defaultsForCreate) }
                )
            } else {
                taskStack(tasks: tasks, listKey: listKey)
            }
        }
    }

    func taskStack(
        tasks: [TaskItem],
        listKey: String,
        sectionTitle: String? = nil,
        sectionSubtitle: String? = nil,
        sectionIcon: String? = nil,
        sectionTint: Color? = nil
    ) -> some View {
        ReorderableTaskList(
            tasks: tasks,
            listKey: listKey,
            onOpenTask: onOpenTask,
            sectionTitle: sectionTitle,
            sectionSubtitle: sectionSubtitle,
            sectionIcon: sectionIcon,
            sectionTint: sectionTint,
            onPoolMove: onPoolMove,
            onDeleteTask: onDeleteTask,
            onMoreActions: { task in actionTask = task }
        )
        .padding(.top, sectionTitle == nil ? 0 : CueInSpacing.xs)
    }

    struct FieldTaskGroup {
        let id: String
        let title: String
        let icon: String?
        let tint: Color?
        let tasks: [TaskItem]
    }

    func groupedByField(_ tasks: [TaskItem]) -> [FieldTaskGroup] {
        let buckets = Dictionary(grouping: tasks) { $0.fieldID }
        return buckets
            .map { fieldID, tasks in
                if let field = store.field(fieldID) {
                    return FieldTaskGroup(
                        id: field.id.uuidString,
                        title: field.name,
                        icon: field.resolvedIconSystemName,
                        tint: field.color,
                        tasks: tasks
                    )
                }
                return FieldTaskGroup(
                    id: "none",
                    title: "No initiative",
                    icon: "circle.dashed",
                    tint: CueInColors.textTertiary,
                    tasks: tasks
                )
            }
            .sorted { $0.title < $1.title }
    }

    func relativeDayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let diff = cal.dateComponents([.day], from: start, to: date).day ?? 0
        if diff == 1 { return "Tomorrow" }
        if diff > 1 && diff < 7 { return "In \(diff) days" }
        return ""
    }
}

private struct TaskCollectionHeader: View {
    let kind: TaskCollectionKind
    let openCount: Int
    let doneCount: Int
    let onCreate: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CueInSpacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(CueInColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(openCount) open")
                    Text("·")
                    Text("\(doneCount) done")
                }
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
            .accessibilityLabel("New task")
        }
    }
}
