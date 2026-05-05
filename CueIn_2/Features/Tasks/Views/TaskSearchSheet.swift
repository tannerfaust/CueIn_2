import SwiftUI

// MARK: - TaskSearchSheet
/// Full-screen search / "finder" for the Tasks module.
/// Autofocused search field, live grouped results, quick scope chips
/// (All / Today / Inbox / Upcoming / Done), and one-tap open into detail.

struct TaskSearchSheet: View {

    var store: TasksStore
    var onDismiss: () -> Void
    var onOpenTask: (UUID) -> Void

    @MainActor init(onDismiss: @escaping () -> Void, onOpenTask: @escaping (UUID) -> Void) {
        self.store = .shared
        self.onDismiss = onDismiss
        self.onOpenTask = onOpenTask
    }

    @MainActor init(store: TasksStore, onDismiss: @escaping () -> Void, onOpenTask: @escaping (UUID) -> Void) {
        self.store = store
        self.onDismiss = onDismiss
        self.onOpenTask = onOpenTask
    }

    @State private var query: String = ""
    @State private var scope: Scope = .all
    @State private var hapticTrigger = false
    @FocusState private var queryFocused: Bool

    enum Scope: String, CaseIterable, Identifiable {
        case all      = "All"
        case today    = "Today"
        case inbox    = "Inbox"
        case upcoming = "Upcoming"
        case done     = "Done"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .all:      return "tray.full.fill"
            case .today:    return "sun.max.fill"
            case .inbox:    return "tray.fill"
            case .upcoming: return "calendar"
            case .done:     return "checkmark.circle.fill"
            }
        }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            scopeBar
            Divider().background(CueInColors.divider)

            if results.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: CueInSpacing.lg) {
                        ForEach(grouped, id: \.label) { group in
                            resultGroup(label: group.label, tasks: group.tasks, color: group.color)
                        }
                    }
                    .padding(.top, CueInSpacing.md)
                    .padding(.bottom, CueInSpacing.huge)
                }
            }
        }
        .background(CueInColors.background)
        .sensoryFeedback(.selection, trigger: hapticTrigger)
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                queryFocused = true
            }
        }
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: CueInSpacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CueInColors.textSecondary)

                TextField("Search tasks, projects, initiatives…", text: $query)
                    .font(CueInTypography.body)
                    .foregroundStyle(CueInColors.textPrimary)
                    .tint(CueInColors.accentFocus)
                    .focused($queryFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(CueInColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, CueInSpacing.md)
            .padding(.vertical, 10)
            .background(CueInColors.surfacePrimary)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(CueInColors.divider, lineWidth: 0.5)
            )

            Button {
                onDismiss()
            } label: {
                Text("Done")
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.accentFocus)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.top, CueInSpacing.base)
        .padding(.bottom, CueInSpacing.md)
    }

    // MARK: Scope bar

    private var scopeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CueInSpacing.sm) {
                ForEach(Scope.allCases) { s in
                    let on = scope == s
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { scope = s }
                        hapticTrigger.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: s.icon)
                                .font(.system(size: 10, weight: .semibold))
                            Text(s.rawValue)
                                .font(CueInTypography.captionMedium)
                        }
                        .foregroundStyle(on ? CueInColors.textPrimary : CueInColors.textSecondary)
                        .padding(.horizontal, CueInSpacing.md)
                        .padding(.vertical, 6)
                        .background(on ? CueInColors.surfaceSecondary : Color.clear)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().strokeBorder(
                                on ? Color.clear : CueInColors.divider,
                                lineWidth: 0.5
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)
        }
        .padding(.bottom, CueInSpacing.md)
    }

    // MARK: Results grouping

    private var scopedTasks: [TaskItem] {
        switch scope {
        case .all:      return store.tasks.filter { $0.status != .archived }
        case .today:    return store.todayTasks
        case .inbox:    return store.inboxTasks
        case .upcoming: return store.upcomingTasks
        case .done:     return store.tasks.filter(\.isCompleted)
        }
    }

    private var results: [TaskItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let base = scopedTasks
        guard !q.isEmpty else { return base }
        return base.filter { t in
            if t.title.lowercased().contains(q) { return true }
            if t.notes.lowercased().contains(q) { return true }
            if t.tags.contains(where: { $0.lowercased().contains(q) }) { return true }
            if let f = store.field(t.fieldID), f.name.lowercased().contains(q) { return true }
            if let p = store.project(t.projectID), p.name.lowercased().contains(q) { return true }
            return false
        }
    }

    private struct Group {
        let label: String
        let color: Color
        let tasks: [TaskItem]
    }

    private var grouped: [Group] {
        let buckets = Dictionary(grouping: results) { $0.fieldID }
        return buckets
            .map { (fid, tasks) -> Group in
                if let f = store.field(fid) {
                    return Group(label: f.name, color: f.color, tasks: tasks)
                } else {
                    return Group(label: "No initiative", color: CueInColors.textTertiary, tasks: tasks)
                }
            }
            .sorted { $0.label < $1.label }
    }

    // MARK: Result group

    @ViewBuilder
    private func resultGroup(label: String, tasks: [TaskItem], color: Color) -> some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(label.uppercased())
                    .font(Font.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(CueInColors.textTertiary)
                Spacer()
                Text("\(tasks.count)")
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)

            VStack(spacing: 0) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { idx, t in
                    Button {
                        hapticTrigger.toggle()
                        onOpenTask(t.id)
                    } label: {
                        HStack(spacing: CueInSpacing.md) {
                            Image(systemName: t.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14))
                                .foregroundStyle(t.isCompleted
                                                 ? store.color(for: t)
                                                 : CueInColors.textTertiary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title)
                                    .font(CueInTypography.body)
                                    .foregroundStyle(CueInColors.textPrimary)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    if let p = store.project(t.projectID) {
                                        Text(p.name)
                                            .font(CueInTypography.micro)
                                            .foregroundStyle(CueInColors.textTertiary)
                                    }
                                    ExecutionTypeBadge(type: t.executionType)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(CueInColors.textTertiary)
                        }
                        .padding(.horizontal, CueInSpacing.screenHorizontal)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if idx < tasks.count - 1 {
                        Divider()
                            .background(CueInColors.divider)
                            .padding(.leading, CueInSpacing.screenHorizontal + 28)
                    }
                }
            }
            .background(CueInColors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                    .strokeBorder(CueInColors.cardBorder, lineWidth: 0.5)
            )
            .padding(.horizontal, CueInSpacing.screenHorizontal)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: CueInSpacing.md) {
            Image(systemName: query.isEmpty ? "magnifyingglass" : "text.magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(CueInColors.textTertiary)
            Text(query.isEmpty ? "Start typing to search" : "No tasks match \u{201C}\(query)\u{201D}")
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, CueInSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
