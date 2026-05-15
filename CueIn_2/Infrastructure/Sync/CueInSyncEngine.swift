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

    var state: CueInSyncState = .idle

    private init() {
        self.client = SupabaseClient.shared
        self.authStore = SupabaseAuthStore.shared
    }

    func configure(modelContext: ModelContext) {
        repository = LocalSyncRepository(modelContext: modelContext)
    }

    func enqueue<Record: SupabaseSyncRecord>(_ record: Record, table: SupabaseTable) {
        guard let repository else { return }
        do {
            try repository.upsert(record, table: table, enqueueMutation: true)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func syncNow() async {
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
            let now = Date()
            state = .synced(now)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func migrateCurrentWorkspaceIfNeeded(tasksStore: TasksStore, goalStore: GoalStrategyStore) {
        guard let userID = authStore.session?.user.id else { return }
        let key = "cuein.sync.didMigrateWorkspace.\(userID.uuidString)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

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
        UserDefaults.standard.set(true, forKey: key)
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
}
