import Foundation
import Observation
import SwiftData

enum CueInSyncState: Equatable {
    case idle
    case syncing
    case blocked(String)
    case failed(String)
    case synced(Date)
}

@Observable
@MainActor
final class CueInSyncEngine {
    static let shared = CueInSyncEngine()

    private let client: SupabaseClient
    private let authStore: SupabaseAuthStore
    private var repository: LocalSyncRepository?
    private var scheduledSyncTask: Task<Void, Never>?

    var state: CueInSyncState = .idle

    private init() {
        self.client = SupabaseClient.shared
        self.authStore = SupabaseAuthStore.shared
    }

    func configure(modelContext: ModelContext) {
        repository = LocalSyncRepository(modelContext: modelContext)
    }

    func loadCachedWorkspaceForCurrentUser() {
        guard let repository, let userID = authStore.session?.user.id else { return }
        do {
            guard try repository.hasCachedWorkspace(for: userID) else { return }
            try applyCachedWorkspace(repository: repository, userID: userID)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func enqueue<Record: SupabaseSyncRecord>(_ record: Record, table: SupabaseTable) {
        guard let repository else { return }
        do {
            try repository.upsert(record, table: table, enqueueMutation: true)
            scheduleSync()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func syncNow() async {
        scheduledSyncTask?.cancel()
        scheduledSyncTask = nil
        guard let repository else {
            state = .blocked("Local database is not ready.")
            return
        }
        guard var session = authStore.session else {
            state = .blocked("Sign in to sync.")
            return
        }

        state = .syncing
        await authStore.refreshIfNeeded()
        if let refreshed = authStore.session {
            session = refreshed
        }

        do {
            try await pushPendingMutations(repository: repository, session: session)
            try await pullRemoteChanges(repository: repository, session: session)
            try applyCachedWorkspace(repository: repository, userID: session.user.id)
            let now = Date()
            state = .synced(now)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func scheduleSync() {
        guard authStore.session != nil else { return }
        scheduledSyncTask?.cancel()
        scheduledSyncTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self.syncNow()
        }
    }

    func migrateCurrentWorkspaceIfNeeded(tasksStore: TasksStore, goalStore: GoalStrategyStore) {
        guard let repository, let userID = authStore.session?.user.id else { return }
        do {
            if try repository.hasCachedWorkspace(for: userID) {
                try applyCachedWorkspace(repository: repository, userID: userID)
                return
            }
            try repository.clearPendingMutations(for: .goals)
            try repository.clearPendingMutations(for: .appLayoutSettings)
        } catch {
            state = .failed(error.localizedDescription)
        }

        guard CueInAppDataService.isGimmickDemoRemoved else {
            return
        }

        enqueueWorkspaceSnapshot(tasksStore: tasksStore, goalStore: goalStore, userID: userID)
    }

    private func enqueueWorkspaceSnapshot(tasksStore: TasksStore, goalStore: GoalStrategyStore, userID: UUID) {
        let now = Date()
        for field in tasksStore.fields {
            enqueue(FieldDTO(field: field, userID: userID, syncVersion: 1), table: .fields)
        }
        for project in tasksStore.projects {
            enqueue(ProjectDTO(project: project, userID: userID, syncVersion: 1), table: .projects)
        }
        for task in tasksStore.tasks {
            enqueue(TaskDTO(task: task, userID: userID, syncVersion: 1), table: .tasks)
        }
        for goal in goalStore.goals {
            enqueue(GoalDTO(goal: goal, userID: userID, syncVersion: 1), table: .goals)
        }

        let layout = AppLayoutSettingDTO(
            id: UUID(),
            userID: userID,
            key: AppTab.storageKey,
            payload: ["tabs": UserDefaults.standard.string(forKey: AppTab.storageKey) ?? AppTab.storageValue(for: AppTab.defaultTabs)],
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            syncVersion: 1
        )
        enqueue(layout, table: .appLayoutSettings)
    }

    private func pushPendingMutations(repository: LocalSyncRepository, session: SupabaseAuthSession) async throws {
        let mutations = try repository.pendingMutations()
        for mutation in mutations {
            do {
                try await push(mutation, session: session)
                try repository.markSynced(mutation)
            } catch {
                try repository.markFailed(mutation, error: error)
                throw error
            }
        }
    }

    private func push(_ mutation: LocalSyncMutation, session: SupabaseAuthSession) async throws {
        guard let table = SupabaseTable(rawValue: mutation.tableName) else { return }
        guard let payload = mutation.payloadData else { return }
        let decoder = JSONDecoder.cueInSyncDecoder

        switch table {
        case .profiles:
            try await client.upsert([try decoder.decode(ProfileDTO.self, from: payload)], table: table, session: session)
        case .fields:
            try await client.upsert([try decoder.decode(FieldDTO.self, from: payload)], table: table, session: session)
        case .projects:
            try await client.upsert([try decoder.decode(ProjectDTO.self, from: payload)], table: table, session: session)
        case .tasks:
            try await client.upsert([try decoder.decode(TaskDTO.self, from: payload)], table: table, session: session)
        case .goals:
            try await client.upsert([try decoder.decode(GoalDTO.self, from: payload)], table: table, session: session)
        case .scheduleRecords:
            return
        case .appLayoutSettings:
            try await client.upsert([try decoder.decode(AppLayoutSettingDTO.self, from: payload)], table: table, session: session)
        }
    }

    private func pullRemoteChanges(repository: LocalSyncRepository, session: SupabaseAuthSession) async throws {
        try await pull(FieldDTO.self, table: .fields, repository: repository, session: session)
        try await pull(ProjectDTO.self, table: .projects, repository: repository, session: session)
        try await pull(TaskDTO.self, table: .tasks, repository: repository, session: session)
        try await pull(GoalDTO.self, table: .goals, repository: repository, session: session)
        try await pull(AppLayoutSettingDTO.self, table: .appLayoutSettings, repository: repository, session: session)
    }

    private func pull<Record: SupabaseSyncRecord>(
        _ type: Record.Type,
        table: SupabaseTable,
        repository: LocalSyncRepository,
        session: SupabaseAuthSession
    ) async throws {
        let records: [Record] = try await client.fetch(
            type,
            table: table,
            updatedAfter: repository.lastPullDate(for: table),
            session: session
        )
        for record in records {
            try repository.upsert(record, table: table, enqueueMutation: false)
        }
        repository.setLastPullDate(Date(), for: table)
    }

    private func applyCachedWorkspace(repository: LocalSyncRepository, userID: UUID) throws {
        let fields = try repository.records(FieldDTO.self, table: .fields, userID: userID)
            .filter { $0.deletedAt == nil }
            .map(\.domainModel)
            .sorted { $0.createdAt < $1.createdAt }

        let projects = try repository.records(ProjectDTO.self, table: .projects, userID: userID)
            .filter { $0.deletedAt == nil }
            .compactMap(\.domainModel)
            .sorted { $0.createdAt < $1.createdAt }

        let tasks = try repository.records(TaskDTO.self, table: .tasks, userID: userID)
            .filter { $0.deletedAt == nil }
            .map(\.domainModel)
            .sorted { $0.createdAt < $1.createdAt }

        let goals = try repository.records(GoalDTO.self, table: .goals, userID: userID)
            .filter { $0.deletedAt == nil }
            .map(\.domainModel)
            .sorted { $0.createdAt < $1.createdAt }

        TasksStore.shared.replaceFromSync(fields: fields, projects: projects, tasks: tasks)
        GoalStrategyStore.shared.replaceFromSync(goals)
        applyCachedLayoutSettings(repository: repository, userID: userID)
    }

    private func applyCachedLayoutSettings(repository: LocalSyncRepository, userID: UUID) {
        guard let layout = try? repository.records(AppLayoutSettingDTO.self, table: .appLayoutSettings, userID: userID)
            .filter({ $0.deletedAt == nil && $0.key == AppTab.storageKey })
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .first,
            let tabs = layout.payload["tabs"],
            !tabs.isEmpty
        else {
            return
        }

        UserDefaults.standard.set(AppTab.storageValue(for: AppTab.storedTabs(from: tabs)), forKey: AppTab.storageKey)
    }
}
