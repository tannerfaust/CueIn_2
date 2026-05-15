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
    }

    func recordGoalsSnapshot() {
        guard let userID = authStore.session?.user.id else { return }
        for goal in GoalStrategyStore.shared.goals {
            syncEngine.enqueue(GoalDTO(goal: goal, userID: userID), table: .goals)
        }
    }

    func recordGoalsSnapshot(_ goals: [Goal]) {
        guard let userID = authStore.session?.user.id else { return }
        for goal in goals {
            syncEngine.enqueue(GoalDTO(goal: goal, userID: userID), table: .goals)
        }
    }
}
