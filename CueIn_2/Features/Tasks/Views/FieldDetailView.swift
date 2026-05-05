import SwiftUI

// MARK: - FieldDetailView
/// Drill-down view for a single Field. Shows projects + tasks,
/// with a filter across Active / Today / Done.

struct FieldDetailView: View {

    let fieldID: UUID
    var store: TasksStore

    @State private var filter: DetailFilter = .active
    @State private var editingTaskID: UUID? = nil
    @State private var creatingTask = false
    @State private var creatingProject = false
    @State private var editingField = false

    enum DetailFilter: String, CaseIterable, Identifiable {
        case active  = "Active"
        case today   = "Today"
        case done    = "Done"
        case all     = "All"
        var id: String { rawValue }
    }

    private var field: Field? { store.field(fieldID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CueInSpacing.xl) {
                if let field { header(field) }
                projectsBlock
                tasksBlock
            }
            .padding(.bottom, CueInSpacing.huge)
        }
        .background(CueInColors.background)
        .devNotebookScreen(field.map { "Field: \($0.name)" } ?? "Field")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let field {
                    HStack(spacing: 6) {
                        Image(systemName: field.iconName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(field.color)
                        Text(field.name)
                            .font(CueInTypography.bodyMedium)
                            .foregroundStyle(CueInColors.textPrimary)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        creatingTask = true
                    } label: { Label("Add task", systemImage: "plus.circle") }
                    Button {
                        creatingProject = true
                    } label: { Label("Add project", systemImage: "folder.badge.plus") }
                    Button {
                        editingField = true
                    } label: { Label("Edit initiative", systemImage: "pencil") }
                } label: {
                    CueInOverflowMenuGlyph()
                }
            }
        }
        .sheet(isPresented: $creatingTask) {
            TaskDetailSheet(mode: .create, store: store) { creatingTask = false }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(isPresented: $creatingProject) {
            CreateProjectSheet(mode: .create(fieldID: fieldID), store: store) {
                creatingProject = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(isPresented: $editingField) {
            CreateFieldSheet(mode: .edit(fieldID), store: store) { editingField = false }
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
    }

    // MARK: Header

    private func header(_ f: Field) -> some View {
        let stats = store.progress(field: f)
        let progress = stats.total > 0 ? Double(stats.done) / Double(stats.total) : 0
        return VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack(spacing: CueInSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(f.color.opacity(0.14))
                        .frame(width: 56, height: 56)
                    Image(systemName: f.iconName)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(f.color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(f.name)
                        .font(CueInTypography.largeTitle)
                        .foregroundStyle(CueInColors.textPrimary)
                    if !f.summary.isEmpty {
                        Text(f.summary)
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textSecondary)
                    }
                }
                Spacer()
            }

            HStack(spacing: CueInSpacing.md) {
                statChip(value: "\(stats.done)", label: "done", color: f.color)
                statChip(value: "\(stats.total - stats.done)", label: "left",
                         color: CueInColors.textSecondary)
                statChip(value: "\(store.projects(in: f.id).count)", label: "projects",
                         color: CueInColors.textSecondary)
                Spacer()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(CueInColors.surfaceTertiary).frame(height: 4)
                    Capsule().fill(f.color)
                        .frame(width: geo.size.width * progress, height: 4)
                        .animation(.easeInOut(duration: 0.4), value: progress)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.top, CueInSpacing.base)
    }

    @ViewBuilder
    private func statChip(value: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(CueInTypography.captionMedium)
                .foregroundStyle(color)
            Text(label)
                .font(CueInTypography.micro)
                .foregroundStyle(CueInColors.textTertiary)
        }
    }

    // MARK: Projects block

    private var projectsBlock: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack {
                Text("PROJECTS")
                    .font(Font.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(CueInColors.textTertiary)
                Spacer()
                Button { creatingProject = true } label: {
                    Label("New", systemImage: "plus")
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)

            let projects = store.projects(in: fieldID)
            if projects.isEmpty {
                Text("No projects yet")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
                    .padding(.horizontal, CueInSpacing.screenHorizontal)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(projects.enumerated()), id: \.element.id) { idx, p in
                        NavigationLink(value: p.id) {
                            ProjectRow(project: p, store: store)
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
        .navigationDestination(for: UUID.self) { pid in
            ProjectDetailView(projectID: pid, store: store)
        }
    }

    // MARK: Tasks block

    private var tasksBlock: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack {
                Text("TASKS")
                    .font(Font.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(CueInColors.textTertiary)
                Spacer()
                Button { creatingTask = true } label: {
                    Label("New", systemImage: "plus")
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CueInSpacing.sm) {
                    ForEach(DetailFilter.allCases) { f in
                        let on = filter == f
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { filter = f }
                        } label: {
                            Text(f.rawValue)
                                .font(CueInTypography.captionMedium)
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

            let visible = filteredTasks
            if visible.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(CueInColors.textTertiary)
                    Text("Nothing here")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, CueInSpacing.xl)
            } else {
                ReorderableTaskList(
                    tasks: visible,
                    listKey: "field:\(fieldID.uuidString):\(filter.rawValue)",
                    onOpenTask: { editingTaskID = $0 }
                )
                .padding(.horizontal, CueInSpacing.screenHorizontal)
            }
        }
    }

    private var filteredTasks: [TaskItem] {
        let all = store.tasks(in: fieldID)
        switch filter {
        case .all:    return all
        case .active: return all.filter { !$0.isCompleted && $0.status != .archived }
        case .today:  return all.filter { $0.isScheduledToday || $0.status == .active || $0.status == .paused }
        case .done:   return all.filter(\.isCompleted)
        }
    }
}

// MARK: - IdentifiableID helper

struct IdentifiableID: Identifiable, Hashable {
    let id: UUID
}
