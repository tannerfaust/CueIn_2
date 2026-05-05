import SwiftUI

// MARK: - ProjectDetailView
/// Drill-down for a single Project. Rich header with progress, then all its
/// tasks filtered by status.

struct ProjectDetailView: View {

    let projectID: UUID
    var store: TasksStore

    @State private var filter: FieldDetailView.DetailFilter = .active
    @State private var editingTaskID: UUID? = nil
    @State private var creatingTask = false
    @State private var editingProject = false

    private var project: Project? { store.project(projectID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CueInSpacing.xl) {
                if let project { header(project) }
                tasksBlock
            }
            .padding(.bottom, CueInSpacing.huge)
        }
        .background(CueInColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let project {
                    HStack(spacing: 6) {
                        Image(systemName: project.resolvedIconSystemName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(store.color(for: project))
                        Text(project.name)
                            .font(CueInTypography.bodyMedium)
                            .foregroundStyle(CueInColors.textPrimary)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { creatingTask = true } label: {
                        Label("Add task", systemImage: "plus.circle")
                    }
                    Button { editingProject = true } label: {
                        Label("Edit project", systemImage: "pencil")
                    }
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
        .sheet(isPresented: $editingProject) {
            CreateProjectSheet(mode: .edit(projectID), store: store) { editingProject = false }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(item: Binding(
            get: { editingTaskID.map(IdentifiableID.init) },
            set: { editingTaskID = $0?.id }
        )) { wrapped in
            TaskDetailSheet(mode: .edit(wrapped.id), store: store) { editingTaskID = nil }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
    }

    // MARK: Header

    private func header(_ p: Project) -> some View {
        let stats = store.progress(project: p)
        let progress = stats.total > 0 ? Double(stats.done) / Double(stats.total) : 0
        let color = store.color(for: p)
        let parentField = store.field(p.fieldID)

        return VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack(spacing: CueInSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.14))
                        .frame(width: 48, height: 48)
                    Image(systemName: p.resolvedIconSystemName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.name)
                        .font(CueInTypography.title)
                        .foregroundStyle(CueInColors.textPrimary)
                    HStack(spacing: 6) {
                        if let f = parentField {
                            HStack(spacing: 4) {
                                Circle().fill(f.color).frame(width: 6, height: 6)
                                Text(f.name)
                                    .font(CueInTypography.caption)
                                    .foregroundStyle(CueInColors.textSecondary)
                            }
                        }
                        Text("·")
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textTertiary)
                        HStack(spacing: 3) {
                            Image(systemName: p.status.icon)
                                .font(.system(size: 9))
                            Text(p.status.label)
                        }
                        .font(CueInTypography.caption)
                        .foregroundStyle(p.status.tint)
                    }
                }
                Spacer()
            }

            if !p.summary.isEmpty {
                Text(p.summary)
                    .font(CueInTypography.body)
                    .foregroundStyle(CueInColors.textSecondary)
            }

            HStack(spacing: CueInSpacing.md) {
                statChip(value: "\(stats.done)", label: "done", color: color)
                statChip(value: "\(stats.total - stats.done)", label: "left",
                         color: CueInColors.textSecondary)
                if let td = p.targetDate {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9))
                        Text(td, format: .dateTime.month(.abbreviated).day())
                    }
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
                }
                Spacer()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(CueInColors.surfaceTertiary).frame(height: 4)
                    Capsule().fill(color)
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
                    ForEach(FieldDetailView.DetailFilter.allCases) { f in
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
                    Text("No tasks")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                    Button {
                        creatingTask = true
                    } label: {
                        Label("Add task", systemImage: "plus")
                            .font(CueInTypography.captionMedium)
                            .foregroundStyle(CueInColors.accentFocus)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, CueInSpacing.xl)
            } else {
                ReorderableTaskList(
                    tasks: visible,
                    listKey: "project:\(projectID.uuidString):\(filter.rawValue)",
                    onOpenTask: { editingTaskID = $0 }
                )
                .padding(.horizontal, CueInSpacing.screenHorizontal)
            }
        }
    }

    private var filteredTasks: [TaskItem] {
        let all = store.tasksInProject(projectID)
        switch filter {
        case .all:    return all
        case .active: return all.filter { !$0.isCompleted && $0.status != .archived }
        case .today:  return all.filter { $0.isScheduledToday || $0.status == .active || $0.status == .paused }
        case .done:   return all.filter(\.isCompleted)
        }
    }
}
