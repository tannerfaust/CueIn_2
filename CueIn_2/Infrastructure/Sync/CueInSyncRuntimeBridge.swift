import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class CueInSyncRuntimeBridge {
    static let shared = CueInSyncRuntimeBridge()

    private let authStore = SupabaseAuthStore.shared
    private let syncEngine = CueInSyncEngine.shared

    private init() {}

    func configure(modelContext: ModelContext) {
        syncEngine.configure(modelContext: modelContext)
    }

    func migrateAndSyncCurrentWorkspace() async {
        syncEngine.migrateCurrentWorkspaceIfNeeded(
            tasksStore: TasksStore.shared,
            goalStore: GoalStrategyStore.shared
        )
        await syncEngine.syncNow()
    }

    func syncPendingChangesIfSignedIn() async {
        guard authStore.session != nil else { return }
        await syncEngine.syncNow()
    }

    func recordTasksSnapshot() {
        guard let userID = authStore.session?.user.id else { return }
        let store = TasksStore.shared
        syncEngine.enqueue(store.fields.map { FieldDTO(field: $0, userID: userID) }, table: .fields)
        syncEngine.enqueue(store.projects.map { ProjectDTO(project: $0, userID: userID) }, table: .projects)
        syncEngine.enqueue(store.tasks.map { TaskDTO(task: $0, userID: userID) }, table: .tasks)
    }

    func recordDeletedField(_ field: Field) {
        guard let userID = authStore.session?.user.id else { return }
        syncEngine.enqueue(FieldDTO(field: field, userID: userID, deletedAt: Date()), table: .fields)
    }

    func recordDeletedProject(_ project: Project) {
        guard let userID = authStore.session?.user.id else { return }
        syncEngine.enqueue(ProjectDTO(project: project, userID: userID, deletedAt: Date()), table: .projects)
    }

    func recordDeletedTask(_ task: TaskItem) {
        guard let userID = authStore.session?.user.id else { return }
        syncEngine.enqueue(TaskDTO(task: task, userID: userID, deletedAt: Date()), table: .tasks)
    }

    func recordGoalsSnapshot() {
        guard let userID = authStore.session?.user.id else { return }
        syncEngine.enqueue(GoalStrategyStore.shared.goals.map { GoalDTO(goal: $0, userID: userID) }, table: .goals)
    }

    func recordGoalsSnapshot(_ goals: [Goal]) {
        guard let userID = authStore.session?.user.id else { return }
        syncEngine.enqueue(goals.map { GoalDTO(goal: $0, userID: userID) }, table: .goals)
    }

    func recordFormulaLibrarySnapshot() {
        syncEngine.enqueueFormulaLibrarySnapshot()
    }

    func recordAppLayoutSnapshot() {
        syncEngine.enqueueAppLayoutSnapshot()
    }

    func recordDeletedGoal(_ goal: Goal) {
        guard let userID = authStore.session?.user.id else { return }
        syncEngine.enqueue(GoalDTO(goal: goal, userID: userID, deletedAt: Date()), table: .goals)
    }

    func recordWorkspaceDeletion() {
        syncEngine.enqueueWorkspaceDeletion(
            tasksStore: TasksStore.shared,
            goalStore: GoalStrategyStore.shared
        )
    }
}
