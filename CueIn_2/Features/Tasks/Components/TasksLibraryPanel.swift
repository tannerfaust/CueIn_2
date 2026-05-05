import SwiftUI

// MARK: - TasksLibraryPanel
/// Slide-out organization panel for the Tasks tab.
/// Keeps field/project navigation out of the primary task-mode switcher.

struct TasksLibraryPanel: View {

    let store: TasksStore
    let primarySegments: [TasksView.Segment]
    let selectedSegment: TasksView.Segment
    let selectedFieldID: UUID?
    let onClose: () -> Void
    let onSelectSegment: (TasksView.Segment) -> Void
    let onSelectField: (UUID?) -> Void
    let onNewField: () -> Void
    let onNewProject: () -> Void
    let onEditField: (UUID) -> Void
    let onEditProject: (UUID) -> Void
    let onDeleteField: (UUID) -> Void
    let onDeleteProject: (UUID) -> Void
    let onProjectOpened: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.base) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: CueInSpacing.xl) {
                    taskModes
                    fields
                    projects
                }
                .padding(.horizontal, CueInSpacing.base)
                .padding(.bottom, CueInSpacing.xl)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)
        .cueInGlass(
            .roundedRect(cornerRadius: 30),
            tint: Color.white.opacity(0.08),
            interactive: false,
            showsBorder: true,
            borderColor: Color.white.opacity(0.14),
            shadow: CueInGlassShadow(color: Color.black.opacity(0.30), radius: 30, x: 0, y: 16)
        )
    }

    private var header: some View {
        HStack(spacing: CueInSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Task library")
                    .font(CueInTypography.headline)
                    .foregroundStyle(CueInColors.textPrimary)
                Text("Views, fields, and projects")
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
            }

            Spacer(minLength: CueInSpacing.md)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CueInColors.textSecondary)
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
                    .modifier(CueInStableGlassCircleModifier())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close task library")
        }
        .padding(.horizontal, CueInSpacing.base)
        .padding(.top, CueInSpacing.base)
    }

    private var taskModes: some View {
        section(title: "Task modes") {
            VStack(spacing: 4) {
                ForEach(primarySegments) { segment in
                    button(
                        title: segment.rawValue,
                        subtitle: segmentSubtitle(for: segment),
                        icon: segment.icon,
                        tint: tint(for: segment),
                        count: count(for: segment),
                        isActive: selectedSegment == segment && selectedFieldID == nil
                    ) {
                        onSelectSegment(segment)
                    }
                }
            }
        }
    }

    private var fields: some View {
        section(
            title: "Fields",
            actionTitle: "New field",
            actionIcon: "plus",
            action: onNewField
        ) {
            VStack(spacing: 4) {
                button(
                    title: "All fields",
                    subtitle: "Grouped by area",
                    icon: "square.grid.2x2.fill",
                    tint: CueInColors.textSecondary,
                    count: activeTaskCount(fieldID: nil),
                    isActive: selectedSegment == .all && selectedFieldID == nil
                ) {
                    onSelectField(nil)
                }

                ForEach(store.fields) { field in
                    button(
                        title: field.name,
                        subtitle: field.summary.isEmpty ? "\(store.projects(in: field.id).count) projects" : field.summary,
                        icon: field.resolvedIconSystemName,
                        tint: field.color,
                        count: activeTaskCount(fieldID: field.id),
                        isActive: selectedSegment == .all && selectedFieldID == field.id
                    ) {
                        onSelectField(field.id)
                    }
                    .contextMenu {
                        Button {
                            onEditField(field.id)
                        } label: { Label("Edit field", systemImage: "pencil") }

                        Button(role: .destructive) {
                            onDeleteField(field.id)
                        } label: { Label("Delete field", systemImage: "trash") }
                    }
                }

                button(
                    title: "Manage fields",
                    subtitle: "Open the full field view",
                    icon: TasksView.Segment.fields.icon,
                    tint: CueInColors.accentRoutine,
                    count: store.fields.count,
                    isActive: selectedSegment == .fields
                ) {
                    onSelectSegment(.fields)
                }
            }
        }
    }

    private var projects: some View {
        section(
            title: "Projects",
            actionTitle: "New project",
            actionIcon: "plus",
            action: onNewProject
        ) {
            VStack(spacing: 4) {
                button(
                    title: "Project overview",
                    subtitle: "Browse by field",
                    icon: TasksView.Segment.projects.icon,
                    tint: CueInColors.accentFixed,
                    count: store.projects.count,
                    isActive: selectedSegment == .projects
                ) {
                    onSelectSegment(.projects)
                }

                ForEach(store.projects) { project in
                    NavigationLink(value: ProjectRoute(id: project.id)) {
                        rowContent(
                            title: project.name,
                            subtitle: store.field(project.fieldID)?.name ?? "No field",
                            icon: project.resolvedIconSystemName,
                            tint: store.color(for: project),
                            count: activeTaskCount(projectID: project.id),
                            isActive: false
                        )
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded(onProjectOpened))
                    .contextMenu {
                        Button {
                            onEditProject(project.id)
                        } label: { Label("Edit project", systemImage: "pencil") }

                        Button(role: .destructive) {
                            onDeleteProject(project.id)
                        } label: { Label("Delete project", systemImage: "trash") }
                    }
                }
            }
        }
    }

    private func section<Content: View>(
        title: String,
        actionTitle: String? = nil,
        actionIcon: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            HStack(spacing: CueInSpacing.sm) {
                Text(title.uppercased())
                    .font(Font.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(CueInColors.textTertiary)

                Spacer(minLength: CueInSpacing.sm)

                if let actionTitle, let actionIcon, let action {
                    Button(action: action) {
                        Label(actionTitle, systemImage: actionIcon)
                            .labelStyle(.iconOnly)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CueInColors.textSecondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(actionTitle)
                }
            }
            .padding(.horizontal, 4)

            content()
        }
    }

    private func button(
        title: String,
        subtitle: String?,
        icon: String,
        tint: Color,
        count: Int?,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            rowContent(
                title: title,
                subtitle: subtitle,
                icon: icon,
                tint: tint,
                count: count,
                isActive: isActive
            )
        }
        .buttonStyle(.plain)
    }

    private func rowContent(
        title: String,
        subtitle: String?,
        icon: String,
        tint: Color,
        count: Int?,
        isActive: Bool
    ) -> some View {
        HStack(spacing: CueInSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(isActive ? 0.20 : 0.12))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: CueInSpacing.sm)

            if let count {
                Text("\(count)")
                    .font(Font.system(size: 11, weight: .semibold))
                    .foregroundStyle(isActive ? tint : CueInColors.textTertiary)
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isActive ? tint.opacity(0.13) : CueInColors.surfaceTertiary.opacity(0.42))
                    )
            }
        }
        .padding(.horizontal, CueInSpacing.sm)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isActive ? Color.white.opacity(0.085) : Color.white.opacity(0.025))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isActive ? tint.opacity(0.28) : Color.clear, lineWidth: 0.7)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func tint(for segment: TasksView.Segment) -> Color {
        switch segment {
        case .today: return CueInColors.accentFixed
        case .inbox: return CueInColors.textSecondary
        case .upcoming: return CueInColors.accentFocus
        case .all: return CueInColors.accentRoutine
        case .fields: return CueInColors.accentRoutine
        case .projects: return CueInColors.accentFixed
        }
    }

    private func segmentSubtitle(for segment: TasksView.Segment) -> String {
        switch segment {
        case .today: return "Execution pool"
        case .inbox: return "Waiting tasks"
        case .upcoming: return "Scheduled ahead"
        case .all: return selectedFieldID.flatMap(store.field)?.name ?? "Every open task"
        case .fields: return "Areas of work"
        case .projects: return "Project library"
        }
    }

    private func count(for segment: TasksView.Segment) -> Int? {
        switch segment {
        case .today: return store.todayTasks.filter { !$0.isCompleted }.count
        case .inbox: return store.inboxTasks.count
        case .upcoming: return store.upcomingTasks.count
        case .all: return store.activeTasks.count
        case .fields: return store.fields.count
        case .projects: return store.projects.count
        }
    }

    private func activeTaskCount(fieldID: UUID?) -> Int {
        store.activeTasks.filter { task in
            guard let fieldID else { return true }
            return task.fieldID == fieldID
        }.count
    }

    private func activeTaskCount(projectID: UUID) -> Int {
        store.activeTasks.filter { $0.projectID == projectID }.count
    }
}
