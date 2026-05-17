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
        for field in TasksStore.shared.fields {
            syncEngine.enqueue(FieldDTO(field: field, userID: userID), table: .fields)
        }
        for project in TasksStore.shared.projects {
            syncEngine.enqueue(ProjectDTO(project: project, userID: userID), table: .projects)
        }
        for task in TasksStore.shared.tasks {
            syncEngine.enqueue(TaskDTO(task: task, userID: userID), table: .tasks)
        }
        requestAutoSync()
    }

    func recordDeletedField(_ field: Field) {
        guard let userID = authStore.session?.user.id else { return }
        syncEngine.enqueue(FieldDTO(field: field, userID: userID, deletedAt: Date()), table: .fields)
        requestAutoSync()
    }

    func recordDeletedProject(_ project: Project) {
        guard let userID = authStore.session?.user.id else { return }
        syncEngine.enqueue(ProjectDTO(project: project, userID: userID, deletedAt: Date()), table: .projects)
        requestAutoSync()
    }

    func recordDeletedTask(_ task: TaskItem) {
        guard let userID = authStore.session?.user.id else { return }
        syncEngine.enqueue(TaskDTO(task: task, userID: userID, deletedAt: Date()), table: .tasks)
        requestAutoSync()
    }

    func recordGoalsSnapshot() {
        guard let userID = authStore.session?.user.id else { return }
        for goal in GoalStrategyStore.shared.goals {
            syncEngine.enqueue(GoalDTO(goal: goal, userID: userID), table: .goals)
        }
        requestAutoSync()
    }

    func recordGoalsSnapshot(_ goals: [Goal]) {
        guard let userID = authStore.session?.user.id else { return }
        for goal in goals {
            syncEngine.enqueue(GoalDTO(goal: goal, userID: userID), table: .goals)
        }
        requestAutoSync()
    }

    func recordFormulaLibrarySnapshot() {
        syncEngine.enqueueFormulaLibrarySnapshot()
        requestAutoSync()
    }

    func recordAppLayoutSnapshot() {
        syncEngine.enqueueAppLayoutSnapshot()
        requestAutoSync()
    }

    func recordDeletedGoal(_ goal: Goal) {
        guard let userID = authStore.session?.user.id else { return }
        syncEngine.enqueue(GoalDTO(goal: goal, userID: userID, deletedAt: Date()), table: .goals)
        requestAutoSync()
    }

    func recordWorkspaceDeletion() {
        syncEngine.enqueueWorkspaceDeletion(
            tasksStore: TasksStore.shared,
            goalStore: GoalStrategyStore.shared
        )
        requestAutoSync()
    }

    private func requestAutoSync() {
        guard authStore.session != nil else { return }
        Task { @MainActor in
            await syncEngine.syncNow()
        }
    }
}
