import SwiftUI

// MARK: - TasksView
/// Root of the Tasks tab.
/// Hosts a NavigationStack, subtitle under the large title, and
/// a scrollable segmented control that switches between six modes:
/// `All`, `Inbox`, `Today`, `Upcoming`, `Fields`, `Projects`.
/// Search uses the system field (pull down under the large title), like iOS.
///
/// All state lives in `TasksStore.shared`. This view only observes.

struct TasksView: View {

    @Bindable private var store: TasksStore
    @State private var segment: Segment = .today
    @State private var searchText: String = ""
    @State private var isSearchVisible = false
    @State private var selectedFieldID: UUID? = nil

    @State private var editingTaskID: UUID? = nil
    @State private var creatingTask = false
    @State private var creatingField = false
    @State private var creatingProject = false

    // Field / project editing via context menu
    @State private var editingFieldID: UUID? = nil
    @State private var editingProjectID: UUID? = nil

    // Haptics
    @State private var segmentHaptic = false
    @State private var knownTodayTaskIDs: Set<UUID> = []
    @FocusState private var searchFocused: Bool

    @MainActor init() {
        self.store = .shared
    }

    // MARK: Segment

    enum Segment: String, CaseIterable, Identifiable {
        case today    = "Today"
        case inbox    = "Inbox"
        case upcoming = "Upcoming"
        case all      = "All"
        case fields   = "Fields"
        case projects = "Projects"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .today:    return "sun.max.fill"
            case .inbox:    return "tray.fill"
            case .upcoming: return "calendar"
            case .all:      return "list.bullet"
            case .fields:   return "square.grid.2x2.fill"
            case .projects: return "folder.fill"
            }
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isSearchVisible {
                        pullDownSearchField
                            .padding(.horizontal, CueInSpacing.screenHorizontal)
                            .padding(.top, 10)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    tasksHeader
                        .padding(.horizontal, CueInSpacing.screenHorizontal)
                        .padding(.top, isSearchVisible ? CueInSpacing.md : 14)
                    Text(subtitle)
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textSecondary)
                        .padding(.horizontal, CueInSpacing.screenHorizontal)
                        .padding(.top, 6)
                    segmentBar
                        .padding(.top, CueInSpacing.md)
                    Divider()
                        .background(CueInColors.divider)
                        .padding(.top, CueInSpacing.base)

                    content
                        .padding(.top, CueInSpacing.base)
                }
                .padding(.bottom, CueInLayout.scrollBottomInset)
            }
            .background(CueInColors.background)
            .simultaneousGesture(revealSearchGesture)
            .onAppear {
                knownTodayTaskIDs = Set(store.todayTasks.map(\.id))
            }
            .onChange(of: store.todayTasks.map(\.id)) { _, newIDs in
                handleTodayPoolIDsChanged(newIDs)
            }
            .onChange(of: searchFocused) { _, focused in
                guard !focused, searchText.isEmpty else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isSearchVisible = false
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sensoryFeedback(.selection, trigger: segmentHaptic)
            .navigationDestination(for: FieldRoute.self) { route in
                FieldDetailView(fieldID: route.id, store: store)
            }
            .navigationDestination(for: ProjectRoute.self) { route in
                ProjectDetailView(projectID: route.id, store: store)
            }
            .sheet(isPresented: $creatingTask) {
                TaskDetailSheet(mode: .create, store: store) { creatingTask = false }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
            }
            .sheet(isPresented: $creatingField) {
                CreateFieldSheet(mode: .create, store: store) { creatingField = false }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
            }
            .sheet(isPresented: $creatingProject) {
                CreateProjectSheet(mode: .create(fieldID: nil), store: store) {
                    creatingProject = false
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
            }
            .sheet(item: Binding(
                get: { editingTaskID.map(IdentifiableID.init) },
                set: { editingTaskID = $0?.id }
            )) { wrapped in
                TaskDetailSheet(mode: .edit(wrapped.id), store: store) {
                    editingTaskID = nil
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
            }
            .sheet(item: Binding(
                get: { editingFieldID.map(IdentifiableID.init) },
                set: { editingFieldID = $0?.id }
            )) { wrapped in
                CreateFieldSheet(mode: .edit(wrapped.id), store: store) {
                    editingFieldID = nil
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
            }
            .sheet(item: Binding(
                get: { editingProjectID.map(IdentifiableID.init) },
                set: { editingProjectID = $0?.id }
            )) { wrapped in
                CreateProjectSheet(mode: .edit(wrapped.id), store: store) {
                    editingProjectID = nil
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
            }
        }
    }

    private var revealSearchGesture: some Gesture {
        DragGesture(minimumDistance: 28, coordinateSpace: .local)
            .onEnded { value in
                let mostlyVertical = abs(value.translation.width) < 42
                guard mostlyVertical, value.translation.height > 54 else { return }
                revealSearch()
            }
    }

    private func revealSearch() {
        guard !isSearchVisible else {
            searchFocused = true
            return
        }
        withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
            isSearchVisible = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            searchFocused = true
        }
    }

    private func dismissSearch() {
        searchFocused = false
        searchText = ""
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isSearchVisible = false
        }
    }

    private var pullDownSearchField: some View {
        HStack(spacing: CueInSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CueInColors.textTertiary)

            TextField("Search tasks, projects, fields", text: $searchText)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textPrimary)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if isSearchVisible {
                Button {
                    dismissSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CueInColors.textTertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close search")
            }
        }
        .padding(.leading, CueInSpacing.md)
        .padding(.trailing, 8)
        .frame(height: 42)
        .background(CueInColors.surfaceSecondary.opacity(0.80), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(CueInColors.cardBorder, lineWidth: 0.5)
        }
    }

    private var tasksHeader: some View {
        HStack(alignment: .center, spacing: CueInSpacing.md) {
            Text("Tasks")
                .font(.system(size: 42, weight: .bold, design: .default))
                .foregroundStyle(CueInColors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: CueInSpacing.md)
            tasksOverflowMenu
        }
    }

    private var tasksOverflowMenu: some View {
        Menu {
            Button { creatingTask = true } label: {
                Label("New task", systemImage: "checklist")
            }
            Button { creatingProject = true } label: {
                Label("New project", systemImage: "folder.badge.plus")
            }
            Button { creatingField = true } label: {
                Label("New field", systemImage: "square.grid.2x2")
            }
        } label: {
            CueInOverflowMenuGlyph()
        }
        .menuStyle(.borderlessButton)
        .cueInMenuInteractionStability()
    }

    private func showPoolActionToast(task: TaskItem, added: Bool) {
        if added {
            CueInToastCenter.shared.show(
                icon: "bolt.fill",
                title: "Added to Today",
                message: task.title,
                tint: CueInColors.accentFixed
            ) {
                TodayViewModel.shared.dequeuePlannerTask(task.id)
            }
        } else {
            CueInToastCenter.shared.show(
                icon: "tray.fill",
                title: "Moved to Inbox",
                message: task.title
            ) {
                TodayViewModel.shared.enqueuePlannerTask(task)
            }
        }
    }

    private func handleTodayPoolIDsChanged(_ newIDs: [UUID]) {
        let newSet = Set(newIDs)
        let addedIDs = newSet.subtracting(knownTodayTaskIDs)
        let removedIDs = knownTodayTaskIDs.subtracting(newSet)
        knownTodayTaskIDs = newSet

        if let id = addedIDs.first,
           let task = store.tasks.first(where: { $0.id == id && !$0.isCompleted }) {
            showPoolActionToast(task: task, added: true)
            return
        }

        if let id = removedIDs.first,
           let task = store.tasks.first(where: { $0.id == id && !$0.isCompleted }) {
            showPoolActionToast(task: task, added: false)
        }
    }

    private func deleteTaskWithUndo(_ task: TaskItem, listKey: String) {
        store.deleteTask(task.id)
        CueInToastCenter.shared.show(
            icon: "trash.fill",
            title: "Task deleted",
            message: task.title,
            tint: Color(hex: 0x64A8FF)
        ) {
            store.restoreTask(task, listKey: listKey)
            if Calendar.current.isDateInToday(task.scheduledDate ?? .distantPast) {
                TodayViewModel.shared.enqueuePlannerTask(task)
            }
        }
    }

    private var subtitle: String {
        let active = store.activeTasks.count
        let done = store.completedTodayTasks.count
        return "\(active) open · \(done) completed today"
    }

    // MARK: Segment bar

    private var segmentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CueInSpacing.lg) {
                ForEach(Segment.allCases) { seg in
                    segmentButton(seg)
                }
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)
        }
    }

    @ViewBuilder
    private func segmentButton(_ seg: Segment) -> some View {
        let on = segment == seg
        Button {
            guard segment != seg else { return }
            segmentHaptic.toggle()
            withAnimation(.easeInOut(duration: 0.18)) {
                segment = seg
                selectedFieldID = nil
            }
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: seg.icon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(seg.rawValue)
                        .font(CueInTypography.bodyMedium)
                    if let badge = badgeCount(for: seg) {
                        Text("\(badge)")
                            .font(Font.system(size: 10, weight: .semibold))
                            .foregroundStyle(on ? CueInColors.textPrimary : CueInColors.textTertiary)
                            .monospacedDigit()
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(on
                                               ? CueInColors.surfaceSecondary
                                               : CueInColors.surfaceTertiary.opacity(0.6))
                            )
                    }
                }
                .foregroundStyle(on ? CueInColors.textPrimary : CueInColors.textTertiary)

                Rectangle()
                    .fill(on ? CueInColors.accentFocus : Color.clear)
                    .frame(height: 2)
                    .clipShape(Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func badgeCount(for seg: Segment) -> Int? {
        switch seg {
        case .today:    let n = store.todayTasks.filter { !$0.isCompleted }.count
                        return n > 0 ? n : nil
        case .inbox:    let n = store.inboxTasks.count;    return n > 0 ? n : nil
        case .upcoming: let n = store.upcomingTasks.count; return n > 0 ? n : nil
        case .all, .fields, .projects: return nil
        }
    }

    // MARK: Content router

    @ViewBuilder
    private var content: some View {
        switch segment {
        case .today:    todayList
        case .inbox:    inboxList
        case .upcoming: upcomingList
        case .all:      allList
        case .fields:   fieldsGrid
        case .projects: projectsList
        }
    }

    // MARK: Today list

    private var todayList: some View {
        let tasks = filtered(store.todayTasks)
        return Group {
            if tasks.isEmpty {
                emptyState(icon: "bolt", title: "Execution pool is empty", message: "Tap the lightning button on a task to make it executable today.")
            } else {
                groupedByField(tasks, orderKeyPrefix: "today:field:")
            }
        }
    }

    // MARK: Inbox list

    private var inboxList: some View {
        let tasks = filtered(store.inboxTasks)
        return Group {
            if tasks.isEmpty {
                emptyState(icon: "tray", title: "Inbox is clear", message: "Use the add button beside the tabs to capture a task.")
            } else {
                reorderableTaskStack(tasks: tasks, listKey: "inbox")
            }
        }
    }

    // MARK: Upcoming list (grouped by day)

    private var upcomingList: some View {
        let tasks = filtered(store.upcomingTasks)
        let grouped = Dictionary(grouping: tasks) { t -> Date in
            Calendar.current.startOfDay(for: t.scheduledDate ?? .distantFuture)
        }
        let days = grouped.keys.sorted()
        return Group {
            if tasks.isEmpty {
                emptyState(icon: "calendar", title: "No upcoming tasks", message: "Schedule something for the future.")
            } else {
                VStack(spacing: CueInSpacing.sm) {
                    ForEach(days, id: \.self) { day in
                        dayGroup(day: day, tasks: grouped[day] ?? [])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayGroup(day: Date, tasks: [TaskItem]) -> some View {
        let dayTitle = day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        let rel = relativeDayLabel(day)
        reorderableTaskStack(
            tasks: tasks,
            listKey: store.upcomingListKey(day: day),
            sectionTitle: dayTitle,
            sectionSubtitle: rel.isEmpty ? nil : rel
        )
    }

    private func relativeDayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let diff = cal.dateComponents([.day], from: start, to: date).day ?? 0
        if diff == 1 { return "Tomorrow" }
        if diff < 7 { return "In \(diff) days" }
        return ""
    }

    // MARK: All list (grouped by field + field pills)

    private var allList: some View {
        let base = store.tasks.filter { $0.status != .archived }
        let scoped = filtered(base)

        return VStack(spacing: CueInSpacing.md) {
            fieldPillsBar
            if scoped.isEmpty {
                emptyState(icon: "checkmark.circle", title: "Nothing here", message: "Try a different filter.")
            } else {
                groupedByField(scoped, orderKeyPrefix: "all:field:")
            }
        }
    }

    private var fieldPillsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CueInSpacing.sm) {
                pill(
                    label: "All fields",
                    active: selectedFieldID == nil,
                    color: CueInColors.textPrimary
                ) { selectedFieldID = nil }

                ForEach(store.fields) { f in
                    pill(
                        label: f.name,
                        active: selectedFieldID == f.id,
                        color: f.color,
                        dot: true
                    ) {
                        selectedFieldID = selectedFieldID == f.id ? nil : f.id
                    }
                }
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)
        }
    }

    @ViewBuilder
    private func pill(label: String, active: Bool, color: Color, dot: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if dot { Circle().fill(color).frame(width: 5, height: 5) }
                Text(label)
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(active ? color : CueInColors.textSecondary)
            }
            .padding(.horizontal, CueInSpacing.md)
            .padding(.vertical, 6)
            .background(active ? color.opacity(0.12) : Color.clear)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(
                    active ? color.opacity(0.3) : CueInColors.divider,
                    lineWidth: 0.5
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Fields grid

    private var fieldsGrid: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: CueInSpacing.md),
                          GridItem(.flexible(), spacing: CueInSpacing.md)],
                spacing: CueInSpacing.md
            ) {
                ForEach(store.fields) { f in
                    NavigationLink(value: FieldRoute(id: f.id)) {
                        FieldGridCard(field: f, store: store)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            editingFieldID = f.id
                        } label: { Label("Edit field", systemImage: "pencil") }

                        Button {
                            creatingProject = true
                        } label: { Label("New project here", systemImage: "folder.badge.plus") }

                        Divider()

                        Button(role: .destructive) {
                            withAnimation { store.deleteField(f.id) }
                        } label: { Label("Delete field", systemImage: "trash") }
                    }
                }
                newFieldTile
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)
        }
    }

    private var newFieldTile: some View {
        Button { creatingField = true } label: {
            VStack(alignment: .leading, spacing: CueInSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(CueInColors.textTertiary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3]))
                        .frame(width: 36, height: 36)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CueInColors.textTertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("New field")
                        .font(CueInTypography.headline)
                        .foregroundStyle(CueInColors.textSecondary)
                    Text("An area of work")
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(CueInSpacing.base)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                    .strokeBorder(CueInColors.divider, style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Projects list (grouped by field)

    private var projectsList: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.xl) {
            ForEach(store.fields) { f in
                let projects = store.projects(in: f.id)
                VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                    HStack(spacing: 5) {
                        Image(systemName: f.iconName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(f.color)
                        Text(f.name.uppercased())
                            .font(Font.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(CueInColors.textTertiary)
                        Spacer()
                        Text("\(projects.count)")
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textTertiary)
                    }
                    .padding(.horizontal, CueInSpacing.screenHorizontal)

                    if projects.isEmpty {
                        Text("No projects yet")
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textTertiary)
                            .padding(.horizontal, CueInSpacing.screenHorizontal)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(projects.enumerated()), id: \.element.id) { idx, p in
                                NavigationLink(value: ProjectRoute(id: p.id)) {
                                    ProjectRow(project: p, store: store)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        editingProjectID = p.id
                                    } label: { Label("Edit project", systemImage: "pencil") }

                                    Button {
                                        creatingTask = true
                                    } label: { Label("New task", systemImage: "plus") }

                                    Divider()

                                    Button(role: .destructive) {
                                        withAnimation { store.deleteProject(p.id) }
                                    } label: { Label("Delete project", systemImage: "trash") }
                                }
                                if idx < projects.count - 1 {
                                    Divider()
                                        .background(CueInColors.divider)
                                        .padding(.leading, CueInSpacing.screenHorizontal + 38)
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
            }

            Button { creatingProject = true } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("New project")
                        .fontWeight(.medium)
                    Spacer()
                }
                .foregroundStyle(CueInColors.textSecondary)
                .padding(.horizontal, CueInSpacing.base)
                .padding(.vertical, CueInSpacing.md)
                .background(CueInColors.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
                .padding(.horizontal, CueInSpacing.screenHorizontal)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Shared task renderers

    private func filtered(_ tasks: [TaskItem]) -> [TaskItem] {
        var result = tasks
        if !searchText.isEmpty {
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            result = result.filter { t in
                if t.title.localizedCaseInsensitiveContains(q) { return true }
                if t.notes.localizedCaseInsensitiveContains(q) { return true }
                if t.tags.contains(where: { $0.localizedCaseInsensitiveContains(q) }) { return true }
                if let f = store.field(t.fieldID), f.name.localizedCaseInsensitiveContains(q) { return true }
                if let p = store.project(t.projectID), p.name.localizedCaseInsensitiveContains(q) { return true }
                return false
            }
        }
        if let fid = selectedFieldID {
            result = result.filter { $0.fieldID == fid }
        }
        return result
    }

    @ViewBuilder
    private func reorderableTaskStack(
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
            onOpenTask: { editingTaskID = $0 },
            sectionTitle: sectionTitle,
            sectionSubtitle: sectionSubtitle,
            sectionIcon: sectionIcon,
            sectionTint: sectionTint,
            onPoolMove: { task, added in
                showPoolActionToast(task: task, added: added)
            },
            onDeleteTask: { task, key in
                deleteTaskWithUndo(task, listKey: key)
            }
        )
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    @ViewBuilder
    private func groupedByField(_ tasks: [TaskItem], orderKeyPrefix: String) -> some View {
        let groups: [(field: Field?, items: [TaskItem])] = {
            var dict: [UUID?: [TaskItem]] = [:]
            for t in tasks { dict[t.fieldID, default: []].append(t) }
            return dict
                .map { ($0.key.flatMap(store.field), $0.value) }
                .sorted { ($0.field?.name ?? "ZZZ") < ($1.field?.name ?? "ZZZ") }
        }()

        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                let done = group.items.filter(\.isCompleted).count
                let name = group.field?.name ?? "No field"
                reorderableTaskStack(
                    tasks: group.items,
                    listKey: "\(orderKeyPrefix)\(group.field?.id.uuidString ?? "none")",
                    sectionTitle: name,
                    sectionSubtitle: "\(done)/\(group.items.count)",
                    sectionIcon: group.field?.iconName,
                    sectionTint: group.field?.color
                )
            }
        }
    }

    // MARK: Empty state

    @ViewBuilder
    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: CueInSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(CueInColors.textTertiary)
            Text(title)
                .font(CueInTypography.headline)
                .foregroundStyle(CueInColors.textSecondary)
            Text(message)
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, CueInSpacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, CueInSpacing.xxxl)
    }
}

// MARK: - Navigation routes

struct FieldRoute: Hashable { let id: UUID }
struct ProjectRoute: Hashable { let id: UUID }

// MARK: - Preview

#Preview {
    ZStack {
        CueInColors.background.ignoresSafeArea()
        TasksView()
    }
    .preferredColorScheme(.dark)
}
