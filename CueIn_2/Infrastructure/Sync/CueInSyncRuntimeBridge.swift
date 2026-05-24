import Foundation
import Observation
import SwiftData

/// Bridges in-memory `TasksStore` mutations into the sync engine + integration push pipeline.
///
/// Three important non-obvious behaviors:
///
/// 1. Per-record enqueue (not full-list).
///    `recordChangedTask/Project/Field` enqueue exactly one DTO. The legacy
///    `recordWorkspaceSnapshot()` is reserved for bulk operations (gimmick reseed,
///    workspace clear, post-migration enqueue) — never called from CRUD paths.
///
/// 2. Per-integration immediate-push debouncer.
///    A flurry of edits (drag-reorder, multi-toggle, AI batch) used to fire one
///    `linear-sync` / `notion-sync` edge-function call *per* edit. We coalesce
///    rapid pushes by integration: each `triggerImmediatePush` schedules a single
///    push 600ms later; subsequent calls within that window reset the timer.
///
/// 3. Per-record integration push targets.
///    Every `triggerImmediatePush(forTask:)` accumulates the affected task id
///    into a per-integration "dirty set". When the debounced timer fires, the
///    set is drained and sent to the edge function as `targets.task_ids`, so
///    the server pushes only those rows instead of scanning the user's whole
///    `tasks` table. Manual "Sync all" / scheduled pulls do not populate the
///    set and so still trigger a full scan.
@Observable
@MainActor
final class CueInSyncRuntimeBridge {
    static let shared = CueInSyncRuntimeBridge()

    private let authStore = SupabaseAuthStore.shared
    private let syncEngine = CueInSyncEngine.shared

    var isApplyingSyncPayload = false

    private var pendingNotionPush: Task<Void, Never>?
    private var pendingLinearPush: Task<Void, Never>?
    private var pendingCloudPush: Task<Void, Never>?
    private var dirtyNotionTaskIDs: Set<UUID> = []
    private var dirtyNotionProjectIDs: Set<UUID> = []
    private var dirtyLinearTaskIDs: Set<UUID> = []
    private var dirtyLinearProjectIDs: Set<UUID> = []
    private static let immediatePushDebounce: Duration = .milliseconds(600)

    private init() {}

    func configure(modelContext: ModelContext) {
        syncEngine.configure(modelContext: modelContext)
    }

    func migrateAndSyncCurrentWorkspace() async {
        guard !isApplyingSyncPayload else { return }
        syncEngine.migrateCurrentWorkspaceIfNeeded(
            tasksStore: TasksStore.shared,
            goalStore: GoalStrategyStore.shared
        )
        await syncEngine.syncNow()
    }

    func syncPendingChangesIfSignedIn() async {
        guard !isApplyingSyncPayload else { return }
        guard authStore.session != nil else { return }
        await syncEngine.syncNow()
    }

    // MARK: - Per-record record methods (preferred)

    func recordChangedTask(_ task: TaskItem) {
        guard !isApplyingSyncPayload else { return }
        guard let userID = authStore.session?.user.id else { return }
        syncEngine.enqueue(TaskDTO(task: task, userID: userID), table: .tasks)
    }

    func recordChangedProject(_ project: Project) {
        guard !isApplyingSyncPayload else { return }
        guard let userID = authStore.session?.user.id else { return }
        syncEngine.enqueue(ProjectDTO(project: project, userID: userID), table: .projects)
    }

    func recordChangedField(_ field: Field) {
        guard !isApplyingSyncPayload else { return }
        guard let userID = authStore.session?.user.id else { return }
        syncEngine.enqueue(FieldDTO(field: field, userID: userID), table: .fields)
    }

    /// Bulk-enqueue the entire workspace. Use only for migrations, gimmick reseed,
    /// or full workspace deletion — never from CRUD paths.
    func recordWorkspaceSnapshot() {
        guard !isApplyingSyncPayload else { return }
        guard let userID = authStore.session?.user.id else { return }
        let store = TasksStore.shared
        syncEngine.enqueue(store.fields.map { FieldDTO(field: $0, userID: userID) }, table: .fields)
        syncEngine.enqueue(store.projects.map { ProjectDTO(project: $0, userID: userID) }, table: .projects)
        syncEngine.enqueue(store.tasks.map { TaskDTO(task: $0, userID: userID) }, table: .tasks)
    }

    func recordDeletedField(_ field: Field) {
        guard !isApplyingSyncPayload else { return }
        guard let userID = authStore.session?.user.id else { return }
        syncEngine.enqueue(FieldDTO(field: field, userID: userID, deletedAt: Date()), table: .fields)
    }

    func recordDeletedProject(_ project: Project) {
        guard !isApplyingSyncPayload else { return }
        guard let userID = authStore.session?.user.id else { return }
        syncEngine.enqueue(ProjectDTO(project: project, userID: userID, deletedAt: Date()), table: .projects)
    }

    func recordDeletedTask(_ task: TaskItem) {
        guard !isApplyingSyncPayload else { return }
        guard let userID = authStore.session?.user.id else { return }
        syncEngine.enqueue(TaskDTO(task: task, userID: userID, deletedAt: Date()), table: .tasks)
    }

    func recordGoalsSnapshot() {
        guard !isApplyingSyncPayload else { return }
        guard let userID = authStore.session?.user.id else { return }
        syncEngine.enqueue(GoalStrategyStore.shared.goals.map { GoalDTO(goal: $0, userID: userID) }, table: .goals)
    }

    func recordGoalsSnapshot(_ goals: [Goal]) {
        guard !isApplyingSyncPayload else { return }
        guard let userID = authStore.session?.user.id else { return }
        syncEngine.enqueue(goals.map { GoalDTO(goal: $0, userID: userID) }, table: .goals)
    }

    func recordFormulaLibrarySnapshot() {
        guard !isApplyingSyncPayload else { return }
        syncEngine.enqueueFormulaLibrarySnapshot()
    }

    func recordAppLayoutSnapshot() {
        guard !isApplyingSyncPayload else { return }
        syncEngine.enqueueAppLayoutSnapshot()
    }

    func recordDeletedGoal(_ goal: Goal) {
        guard !isApplyingSyncPayload else { return }
        guard let userID = authStore.session?.user.id else { return }
        syncEngine.enqueue(GoalDTO(goal: goal, userID: userID, deletedAt: Date()), table: .goals)
    }

    func recordWorkspaceDeletion() {
        guard !isApplyingSyncPayload else { return }
        syncEngine.enqueueWorkspaceDeletion(
            tasksStore: TasksStore.shared,
            goalStore: GoalStrategyStore.shared
        )
    }

    // MARK: - Immediate-push routing (debounced per integration, with targets)

    func triggerImmediatePush(forTask task: TaskItem) {
        guard !isApplyingSyncPayload else { return }
        let store = TasksStore.shared
        if store.isNotionTask(task) {
            dirtyNotionTaskIDs.insert(task.id)
            scheduleNotionPush()
        } else if store.isLinearTask(task) {
            dirtyLinearTaskIDs.insert(task.id)
            scheduleLinearPush()
        } else {
            scheduleCloudPush()
        }
    }

    func triggerImmediatePush(forProject project: Project) {
        guard !isApplyingSyncPayload else { return }
        let store = TasksStore.shared
        let parentField = store.field(project.fieldID)
        if project.isNotionImported || parentField?.name.localizedCaseInsensitiveCompare("notion") == .orderedSame {
            dirtyNotionProjectIDs.insert(project.id)
            scheduleNotionPush()
        } else if project.isLinearImported || parentField?.name.localizedCaseInsensitiveCompare("linear") == .orderedSame {
            dirtyLinearProjectIDs.insert(project.id)
            scheduleLinearPush()
        } else {
            scheduleCloudPush()
        }
    }

    func triggerImmediatePush(forField field: Field) {
        guard !isApplyingSyncPayload else { return }
        // Field renames don't have a direct integration counterpart — the field
        // itself isn't pushed to Notion or Linear. We still need the cloud sync,
        // and a downstream task push is what reflects integration scope changes.
        if field.name.localizedCaseInsensitiveCompare("notion") == .orderedSame
            || field.name.localizedCaseInsensitiveCompare("linear") == .orderedSame {
            scheduleCloudPush()
        } else {
            scheduleCloudPush()
        }
    }

    private func scheduleNotionPush() {
        pendingNotionPush?.cancel()
        pendingNotionPush = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.immediatePushDebounce)
            if Task.isCancelled { return }
            guard let self else { return }
            self.pendingNotionPush = nil
            let targets = self.drainNotionTargets()
            await NotionIntegrationStore.shared.syncNow(action: .push, targets: targets)
        }
    }

    private func scheduleLinearPush() {
        pendingLinearPush?.cancel()
        pendingLinearPush = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.immediatePushDebounce)
            if Task.isCancelled { return }
            guard let self else { return }
            self.pendingLinearPush = nil
            let targets = self.drainLinearTargets()
            await LinearIntegrationStore.shared.syncNow(action: .push, targets: targets)
        }
    }

    private func scheduleCloudPush() {
        pendingCloudPush?.cancel()
        pendingCloudPush = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.immediatePushDebounce)
            if Task.isCancelled { return }
            self?.pendingCloudPush = nil
            await CueInSyncEngine.shared.syncNow()
        }
    }

    private func drainNotionTargets() -> NotionSyncTargets? {
        let taskIDs = Array(dirtyNotionTaskIDs)
        let projectIDs = Array(dirtyNotionProjectIDs)
        dirtyNotionTaskIDs.removeAll(keepingCapacity: false)
        dirtyNotionProjectIDs.removeAll(keepingCapacity: false)
        if taskIDs.isEmpty && projectIDs.isEmpty { return nil }
        return NotionSyncTargets(
            taskIDs: taskIDs.isEmpty ? nil : taskIDs,
            projectIDs: projectIDs.isEmpty ? nil : projectIDs
        )
    }

    private func drainLinearTargets() -> LinearSyncTargets? {
        let taskIDs = Array(dirtyLinearTaskIDs)
        let projectIDs = Array(dirtyLinearProjectIDs)
        dirtyLinearTaskIDs.removeAll(keepingCapacity: false)
        dirtyLinearProjectIDs.removeAll(keepingCapacity: false)
        if taskIDs.isEmpty && projectIDs.isEmpty { return nil }
        return LinearSyncTargets(
            taskIDs: taskIDs.isEmpty ? nil : taskIDs,
            projectIDs: projectIDs.isEmpty ? nil : projectIDs
        )
    }
}
