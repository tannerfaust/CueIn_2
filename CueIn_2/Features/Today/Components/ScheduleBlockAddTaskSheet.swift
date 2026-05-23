import SwiftUI

// MARK: - ScheduleBlockAddTaskSheet
/// Quick capture plus navigation to pick an existing task from ``TasksStore``.
/// Shown when linking tasks to a schedule block.

struct ScheduleBlockAddTaskSheet: View {

    @Bindable var store: TasksStore
    var excludedTaskIDs: Set<UUID>
    var captureDefaultsToToday: Bool
    var onPickExisting: (TaskItem) -> Void
    var onQuickCaptureSaved: (TaskItem) -> Void
    var onQuickCaptureExpand: (TaskItem) -> Void
    var onDismiss: () -> Void

    private enum LibraryRoute: Hashable {
        case library
    }

    @State private var path = NavigationPath()
    @State private var isComposing = false

    var body: some View {
        NavigationStack(path: $path) {
            QuickCaptureSheet(
                store: store,
                captureDefaultsToToday: captureDefaultsToToday,
                onSaved: { item in
                    onQuickCaptureSaved(item)
                },
                onDismiss: onDismiss,
                onExpand: onQuickCaptureExpand,
                showsDragHandle: false,
                presentationMode: .compactComposer,
                autoExpandWhenTyping: true,
                onComposingActiveChanged: { isComposing = $0 }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(CueInColors.surfacePrimary)
            .navigationTitle(isComposing ? "" : "Add task")
            .cueInNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isComposing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            onDismiss()
                        }
                        .foregroundStyle(CueInColors.textPrimary)
                    }
                    ToolbarItem(placement: CueInToolbarPlacement.topBarTrailing) {
                        Button {
                            CueInHaptics.impact(.light)
                            path.append(LibraryRoute.library)
                        } label: {
                            Text("Choose from tasks")
                                .font(CueInTypography.caption)
                                .foregroundStyle(CueInColors.textTertiary)
                        }
                        .accessibilityHint("Search your task library")
                    }
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isComposing)
            .navigationDestination(for: LibraryRoute.self) { _ in
                TaskLibraryPickerView(
                    store: store,
                    excludedTaskIDs: excludedTaskIDs,
                    onSelect: { task in
                        onPickExisting(task)
                        onDismiss()
                    }
                )
            }
        }
    }
}

// MARK: - Task library picker

private enum TaskLibraryScope: String, CaseIterable, Identifiable {
    case all
    case today
    case inbox
    case upcoming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .today: return "Today"
        case .inbox: return "Inbox"
        case .upcoming: return "Upcoming"
        }
    }
}

private enum LinkPickerMetrics {
    static let rowRadius: CGFloat = 14
}

private struct TaskLibraryPickerView: View {

    @Bindable var store: TasksStore
    let excludedTaskIDs: Set<UUID>
    let onSelect: (TaskItem) -> Void

    @State private var searchText = ""
    @State private var scope: TaskLibraryScope = .all

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                scopeChips
                    .padding(.bottom, 4)

                if visibleTasks.isEmpty {
                    emptyState
                } else {
                    ForEach(visibleTasks) { task in
                        taskButton(task)
                    }
                }
            }
            .padding(.horizontal, CueInSpacing.base)
            .padding(.top, CueInSpacing.sm)
            .padding(.bottom, 32)
        }
        .background(CueInColors.background)
        .searchable(
            text: $searchText,
            placement: CueInSearchPlacement.navigationBarDrawerAlways,
            prompt: "Search by title, field, or project"
        )
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Choose from tasks")
        .cueInNavigationBarTitleDisplayMode(.large)
    }

    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaskLibraryScope.allCases) { s in
                    let on = scope == s
                    Button {
                        CueInHaptics.impact(.light)
                        scope = s
                    } label: {
                        Text(s.title)
                            .font(CueInTypography.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                on
                                ? CueInColors.accentFocus.opacity(0.22)
                                : CueInColors.surfacePrimary.opacity(0.9)
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        on ? CueInColors.accentFocus.opacity(0.45) : CueInColors.divider.opacity(0.5),
                                        lineWidth: 0.5
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var visibleTasks: [TaskItem] {
        let pool = scopedPool
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [TaskItem]
        if q.isEmpty {
            filtered = pool
        } else {
            filtered = pool.filter { task in
                if task.title.localizedCaseInsensitiveContains(q) { return true }
                if let f = store.field(task.fieldID), f.name.localizedCaseInsensitiveContains(q) { return true }
                if let p = store.project(task.projectID), p.name.localizedCaseInsensitiveContains(q) { return true }
                if task.tags.contains(where: { $0.localizedCaseInsensitiveContains(q) }) { return true }
                return false
            }
        }
        return filtered.sorted(by: sortTasksPair)
    }

    private func sortTasksPair(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.priority.sortWeight != b.priority.sortWeight {
            return a.priority.sortWeight < b.priority.sortWeight
        }
        return a.createdAt > b.createdAt
    }

    private var scopedPool: [TaskItem] {
        let base = store.tasks.filter { task in
            !task.isCompleted && task.status != .archived && !excludedTaskIDs.contains(task.id)
        }
        switch scope {
        case .all:
            return base
        case .today:
            let allow = Set(store.todayTasks.map(\.id))
            return base.filter { allow.contains($0.id) }
        case .inbox:
            return base.filter(\.isInboxed)
        case .upcoming:
            let allow = Set(store.upcomingTasks.map(\.id))
            return base.filter { allow.contains($0.id) }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: scope == .all ? "tray" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(CueInColors.textTertiary)
            Text(emptyTitle)
                .font(CueInTypography.bodyMedium)
                .foregroundStyle(CueInColors.textSecondary)
                .multilineTextAlignment(.center)
            Text(emptySubtitle)
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, CueInSpacing.lg)
    }

    private var emptyTitle: String {
        if !searchText.isEmpty {
            return "No matches"
        }
        if scopedPool.isEmpty {
            return excludedTaskIDs.isEmpty ? "No tasks yet" : "All matching tasks are already here"
        }
        return "Nothing here"
    }

    private var emptySubtitle: String {
        if !searchText.isEmpty {
            return "Try another word, widen the scope above, or create a new task from the previous screen."
        }
        if scope != .all {
            return "Try another scope or search across All."
        }
        return "Add tasks in the Tasks tab, then come back to add them here."
    }

    private func taskButton(_ task: TaskItem) -> some View {
        Button {
            CueInHaptics.impact(.light)
            onSelect(task)
        } label: {
            TaskPickerLinkRow(task: task, store: store)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row

private struct TaskPickerLinkRow: View {
    let task: TaskItem
    let store: TasksStore

    var body: some View {
        HStack(alignment: .center, spacing: CueInSpacing.md) {
            Image(systemName: store.iconName(for: task))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(store.color(for: task))
                .frame(width: 36, height: 36)
                .background(
                    store.color(for: task).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(CueInTypography.body)
                    .foregroundStyle(CueInColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    if let fieldName = store.field(task.fieldID)?.name {
                        Text(fieldName)
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textTertiary)
                            .lineLimit(1)
                    }
                    if let projectName = store.project(task.projectID)?.name {
                        if store.field(task.fieldID)?.name != nil {
                            Text("·")
                                .font(CueInTypography.micro)
                                .foregroundStyle(CueInColors.textTertiary.opacity(0.7))
                        }
                        Text(projectName)
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textTertiary)
                            .lineLimit(1)
                    }
                }

                scheduleBadge
            }

            Spacer(minLength: 8)

            Image(systemName: "link.badge.plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CueInColors.accentFocus.opacity(0.95))
        }
        .padding(CueInSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: LinkPickerMetrics.rowRadius, style: .continuous)
                .fill(CueInColors.surfacePrimary.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LinkPickerMetrics.rowRadius, style: .continuous)
                .strokeBorder(CueInColors.divider.opacity(0.35), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var scheduleBadge: some View {
        let label = scheduleLabel(for: task)
        if !label.isEmpty {
            Text(label)
                .font(CueInTypography.micro.weight(.semibold))
                .foregroundStyle(CueInColors.accentFixed.opacity(0.95))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    CueInColors.accentFixed.opacity(0.12),
                    in: Capsule()
                )
        }
    }

    private func scheduleLabel(for task: TaskItem) -> String {
        if task.isScheduledToday { return "Today" }
        if task.isInboxed { return "Inbox" }
        if let d = task.scheduledDate {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .none
            return fmt.string(from: d)
        }
        return ""
    }
}
