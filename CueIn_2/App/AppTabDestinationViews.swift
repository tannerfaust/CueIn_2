import SwiftUI

// MARK: - ProjectsTabView

struct ProjectsTabView: View {
    @Bindable private var store: TasksStore
    @State private var activeSheet: TasksSheet?

    @MainActor init() {
        self.store = .shared
    }

    var body: some View {
        NavigationStack {
            TaskProjectsPage(
                store: store,
                onCreateProject: { activeSheet = .createProject($0) },
                onEditProject: { activeSheet = .editProject($0) },
                onDeleteProject: deleteProject
            )
            .navigationDestination(for: TasksRoute.self, destination: destination)
            .background(CueInColors.background.ignoresSafeArea())
        }
        .preferredColorScheme(.dark)
        .sheet(item: $activeSheet, content: sheetContent)
    }

    @ViewBuilder
    private func destination(_ route: TasksRoute) -> some View {
        switch route {
        case .project(let id):
            ProjectDetailView(projectID: id, store: store)
        case .field(let id):
            FieldDetailView(fieldID: id, store: store)
        case .projects:
            TaskProjectsPage(
                store: store,
                onCreateProject: { activeSheet = .createProject($0) },
                onEditProject: { activeSheet = .editProject($0) },
                onDeleteProject: deleteProject
            )
        case .collection(let kind):
            TaskCollectionPage(
                kind: kind,
                store: store,
                onOpenTask: { activeSheet = .editTask($0) },
                onCreateTask: { activeSheet = .createTask($0) },
                onPoolMove: showPoolActionToast,
                onDeleteTask: deleteTaskWithUndo
            )
        case .priority:
            TaskPriorityMatrixPage(
                store: store,
                onOpenTask: { activeSheet = .editTask($0) },
                onCreateTask: { activeSheet = .createTask($0) }
            )
        case .initiatives:
            TaskInitiativesPage(
                store: store,
                onCreateField: { activeSheet = .createField },
                onEditField: { activeSheet = .editField($0) },
                onDeleteField: deleteField
            )
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: TasksSheet) -> some View {
        switch sheet {
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
        case .search:
            TaskSearchSheet(
                store: store,
                onDismiss: dismissSheet,
                onOpenTask: { activeSheet = .editTask($0) }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
    }

    private func dismissSheet() {
        activeSheet = nil
    }

    private func deleteField(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            store.deleteField(id)
        }
    }

    private func deleteProject(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            store.deleteProject(id)
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
}

// MARK: - GoalsTabView

struct GoalsTabView: View {
    @State private var path: [GoalStrategyRoute] = []
    @State private var activeGoalSheet: GoalStrategySheet?
    @Bindable private var goalStore = GoalStrategyStore.shared
    @Bindable private var tasksStore = TasksStore.shared

    var body: some View {
        NavigationStack(path: $path) {
            GoalsHomeView(
                store: goalStore,
                tasksStore: tasksStore,
                onCreateGoal: { activeGoalSheet = .createGoal(templateID: $0?.id) },
                onPresentSheet: { activeGoalSheet = $0 }
            )
            .navigationDestination(for: GoalStrategyRoute.self, destination: goalDestination)
        }
        .sheet(item: $activeGoalSheet, content: goalSheetContent)
    }

    @ViewBuilder
    private func goalDestination(_ route: GoalStrategyRoute) -> some View {
        switch route {
        case .home:
            GoalsHomeView(
                store: goalStore,
                tasksStore: tasksStore,
                onCreateGoal: { activeGoalSheet = .createGoal(templateID: $0?.id) },
                onPresentSheet: { activeGoalSheet = $0 }
            )
        case .goal(let id):
            GoalDetailView(
                goalID: id,
                store: goalStore,
                tasksStore: tasksStore,
                onPresentSheet: { activeGoalSheet = $0 }
            )
        }
    }

    @ViewBuilder
    private func goalSheetContent(_ sheet: GoalStrategySheet) -> some View {
        switch sheet {
        case .createGoal, .editGoal:
            GoalEditorSheet(
                sheet: sheet,
                store: goalStore,
                onCreated: { id in path.append(.goal(id)) },
                onDismiss: { activeGoalSheet = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        case .createStage, .editStage:
            GoalStageEditorSheet(
                sheet: sheet,
                store: goalStore,
                onDismiss: { activeGoalSheet = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        case .createSubgoal, .editSubgoal:
            GoalSubgoalEditorSheet(
                sheet: sheet,
                store: goalStore,
                onDismiss: { activeGoalSheet = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        case .linkWork(let goalID, let stageID, let subgoalID):
            GoalWorkLinkPickerSheet(
                goalID: goalID,
                stageID: stageID,
                subgoalID: subgoalID,
                store: goalStore,
                tasksStore: tasksStore,
                onDismiss: { activeGoalSheet = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        case .review(let goalID):
            GoalReviewEntrySheet(
                goalID: goalID,
                store: goalStore,
                onDismiss: { activeGoalSheet = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
    }
}
