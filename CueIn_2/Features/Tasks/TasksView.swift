import SwiftUI

struct TasksView: View {
    @Bindable private var store: TasksStore
    @State private var activeSheet: TasksSheet?
    @State private var knownTodayTaskIDs: Set<UUID> = []

    @MainActor init() {
        self.store = .shared
    }

    var body: some View {
        NavigationStack {
            TasksHomeView(
                store: store,
                onCreateTask: presentCreateTask,
                onOpenTask: presentTask,
                onOpenSearch: presentSearch,
                onCreateField: presentCreateField,
                onCreateProject: presentCreateProject,
                onPoolMove: showPoolActionToast,
                onDeleteTask: deleteTaskWithUndo
            )
            .navigationDestination(for: TasksRoute.self, destination: destination)
            .background(CueInColors.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            knownTodayTaskIDs = Set(store.todayTasks.map(\.id))
        }
        .onChange(of: store.todayTasks.map(\.id)) { _, newIDs in
            handleTodayPoolIDsChanged(newIDs)
        }
        .sheet(item: $activeSheet, content: sheetContent)
    }

    @ViewBuilder
    private func destination(_ route: TasksRoute) -> some View {
        switch route {
        case .collection(let kind):
            TaskCollectionPage(
                kind: kind,
                store: store,
                onOpenTask: presentTask,
                onCreateTask: presentCreateTask,
                onPoolMove: showPoolActionToast,
                onDeleteTask: deleteTaskWithUndo
            )
        case .priority:
            TaskPriorityMatrixPage(
                store: store,
                onOpenTask: presentTask,
                onCreateTask: presentCreateTask
            )
        case .initiatives:
            TaskInitiativesPage(
                store: store,
                onCreateField: presentCreateField,
                onEditField: presentEditField,
                onDeleteField: deleteField
            )
        case .projects:
            TaskProjectsPage(
                store: store,
                onCreateProject: presentCreateProject,
                onEditProject: presentEditProject,
                onDeleteProject: deleteProject
            )
        case .field(let id):
            FieldDetailView(fieldID: id, store: store)
        case .project(let id):
            ProjectDetailView(projectID: id, store: store)
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: TasksSheet) -> some View {
        switch sheet {
        case .createTask(let defaults):
            TaskDetailSheet(
                mode: .create,
                store: store,
                configureCreateDraft: { defaults.apply(to: &$0) },
                onDismiss: dismissSheet
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)

        case .editTask(let id):
            TaskDetailSheet(mode: .edit(id), store: store, onDismiss: dismissSheet)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)

        case .createField:
            CreateFieldSheet(mode: .create, store: store, onDismiss: dismissSheet)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)

        case .editField(let id):
            CreateFieldSheet(mode: .edit(id), store: store, onDismiss: dismissSheet)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)

        case .createProject(let fieldID):
            CreateProjectSheet(mode: .create(fieldID: fieldID), store: store, onDismiss: dismissSheet)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)

        case .editProject(let id):
            CreateProjectSheet(mode: .edit(id), store: store, onDismiss: dismissSheet)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)

        case .search:
            TaskSearchSheet(
                store: store,
                onDismiss: dismissSheet,
                onOpenTask: openTaskFromSearch
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
    }
}

private extension TasksView {
    func presentCreateTask(_ defaults: TaskDraftDefaults = .inbox) {
        activeSheet = .createTask(defaults)
    }

    func presentTask(_ id: UUID) {
        activeSheet = .editTask(id)
    }

    func presentSearch() {
        activeSheet = .search
    }

    func presentCreateField() {
        activeSheet = .createField
    }

    func presentEditField(_ id: UUID) {
        activeSheet = .editField(id)
    }

    func presentCreateProject(_ fieldID: UUID?) {
        activeSheet = .createProject(fieldID)
    }

    func presentEditProject(_ id: UUID) {
        activeSheet = .editProject(id)
    }

    func dismissSheet() {
        activeSheet = nil
    }

    func openTaskFromSearch(_ id: UUID) {
        activeSheet = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            activeSheet = .editTask(id)
        }
    }

    func deleteField(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            store.deleteField(id)
        }
    }

    func deleteProject(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            store.deleteProject(id)
        }
    }

    func deleteTaskWithUndo(_ task: TaskItem, listKey: String) {
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

    func showPoolActionToast(task: TaskItem, added: Bool) {
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

    func handleTodayPoolIDsChanged(_ newIDs: [UUID]) {
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
}

extension TasksView {
    enum Segment: String, CaseIterable, Identifiable {
        case today = "Today"
        case inbox = "Inbox"
        case upcoming = "Upcoming"
        case all = "All"
        case fields = "Fields"
        case projects = "Projects"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .today: return "sun.max.fill"
            case .inbox: return "tray.fill"
            case .upcoming: return "calendar"
            case .all: return "list.bullet"
            case .fields: return "square.grid.2x2.fill"
            case .projects: return "folder.fill"
            }
        }
    }
}

#Preview {
    TasksView()
}
