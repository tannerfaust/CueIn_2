import SwiftUI
import Observation

// MARK: - TasksStore
/// Central in-memory store for Fields, Projects and TaskItems. The single source
/// of truth for the Tasks module.
///
/// Design notes:
/// • `@Observable` — all SwiftUI views observe this directly.
/// • Shared instance — so future Today integration and persistence can plug in
///   without rewiring every view. Today's VM seeds from `MockDataService`; this
///   store also seeds from that set, so the two views are data-consistent.
/// • AI-friendly — smart views (`inboxTasks`, `todayTasks`, etc.) and
///   `planningSnapshot()` give LLM planners a clean API to query and reason on.
/// • Persistence: not yet — swap seeding + add save/load hooks when ready.

@Observable
@MainActor
final class TasksStore {

    static let shared = TasksStore()

    private var suppressSyncRecording = false

    // MARK: State (published)

    var fields: [Field] = []
    var projects: [Project] = []
    var tasks: [TaskItem] = []

    /// Per-list manual ordering (like iOS notification stacks). Keys are owned by callers
    /// (`"inbox"`, `"today:field:\(uuid)"`, `"upcoming:\(dayStart)"`, etc.). Unknown IDs are ignored;
    /// tasks missing from a stored order are appended using `prioritySort`.
    var taskListOrder: [String: [UUID]] = [:]

    /// Tasks the integration sync server flagged as 3-way conflicts (both sides
    /// changed since the last successful sync). Resolved by either pushing
    /// "keep mine" with a force-overwrite flag or pulling the remote version.
    /// Cleared automatically once the server stops returning the conflict for
    /// a given task id on a subsequent push. Persisted to UserDefaults so the
    /// banner survives app relaunches — otherwise a user who closes the app
    /// before resolving silently loses the warning.
    var taskConflicts: [UUID: TaskConflict] = TasksStore.loadPersistedConflicts() {
        didSet { TasksStore.persistConflicts(taskConflicts) }
    }

    private static let conflictsDefaultsKey = "cuein.tasksstore.taskConflicts.v1"

    private static func loadPersistedConflicts() -> [UUID: TaskConflict] {
        guard let data = UserDefaults.standard.data(forKey: conflictsDefaultsKey) else { return [:] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let array = try decoder.decode([TaskConflict].self, from: data)
            return Dictionary(uniqueKeysWithValues: array.map { ($0.cueInID, $0) })
        } catch {
            AppLogger.shared.error(error, message: "Failed to decode persisted task conflicts; resetting")
            UserDefaults.standard.removeObject(forKey: conflictsDefaultsKey)
            return [:]
        }
    }

    private static func persistConflicts(_ conflicts: [UUID: TaskConflict]) {
        if conflicts.isEmpty {
            UserDefaults.standard.removeObject(forKey: conflictsDefaultsKey)
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let array = Array(conflicts.values)
            let data = try encoder.encode(array)
            UserDefaults.standard.set(data, forKey: conflictsDefaultsKey)
        } catch {
            AppLogger.shared.error(error, message: "Failed to persist task conflicts; banner will not survive relaunch")
        }
    }

    /// `true` when at least one task currently has an unresolved sync conflict.
    /// Drives the banner in `TasksView`.
    var hasUnresolvedConflicts: Bool { !taskConflicts.isEmpty }

    /// Full task snapshot from immediately before the user marked a task complete from the Tasks list
    /// (swipe-right or status popover). Used by the shell FAB undo chip; cleared on timeout, undo, or tab change.
    var pendingCompleteUndoSnapshot: TaskItem?

    private var pendingCompleteUndoDismissTask: Task<Void, Never>?

    // MARK: Init

    private init() {
        if CueInAppDataService.isGimmickDemoRemoved {
            self.fields = []
            self.projects = []
            self.tasks = []
            return
        }
        let seed = Self.makeSeed()
        self.fields = seed.fields
        self.projects = seed.projects
        self.tasks = seed.tasks
    }

    // MARK: - Lookups

    func field(_ id: UUID?) -> Field? {
        guard let id else { return nil }
        return fields.first { $0.id == id }
    }

    func project(_ id: UUID?) -> Project? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    func projects(in fieldID: UUID) -> [Project] {
        projects.filter { $0.fieldID == fieldID }
    }

    func tasks(in fieldID: UUID) -> [TaskItem] {
        tasks.filter { $0.fieldID == fieldID }
    }

    func tasksInProject(_ projectID: UUID) -> [TaskItem] {
        tasks.filter { $0.projectID == projectID }
    }

    /// Resolved color for a project — override if set, otherwise parent field's.
    func color(for project: Project) -> Color {
        if let hex = project.colorHexOverride { return Color(hex: hex) }
        return field(project.fieldID)?.color ?? CueInColors.textTertiary
    }

    /// Resolved color for a task — project override → project field → field → neutral.
    func color(for task: TaskItem) -> Color {
        if let proj = project(task.projectID) { return color(for: proj) }
        if let f = field(task.fieldID) { return f.color }
        return CueInColors.textTertiary
    }

    func iconName(for task: TaskItem) -> String {
        if let proj = project(task.projectID) { return proj.resolvedIconSystemName }
        if let f = field(task.fieldID) { return f.resolvedIconSystemName }
        return "circle.dashed"
    }

    func isNotionTask(_ task: TaskItem) -> Bool {
        if task.isNotionImported { return true }
        if let projectID = task.projectID, let proj = project(projectID), proj.isNotionImported { return true }
        if let fieldID = task.fieldID, let f = field(fieldID), f.name.localizedCaseInsensitiveCompare("notion") == .orderedSame { return true }
        if let fieldID = task.fieldID, let userID = SupabaseAuthStore.shared.session?.user.id {
            let notionFieldID = UUID.cueInDeterministicID(userID: userID, key: "field:notion")
            if fieldID == notionFieldID { return true }
        }
        return false
    }

    func isLinearTask(_ task: TaskItem) -> Bool {
        if task.isLinearImported { return true }
        if let projectID = task.projectID, let proj = project(projectID), proj.isLinearImported { return true }
        if let fieldID = task.fieldID, let f = field(fieldID), f.name.localizedCaseInsensitiveCompare("linear") == .orderedSame { return true }
        if let fieldID = task.fieldID, let userID = SupabaseAuthStore.shared.session?.user.id {
            let linearFieldID = UUID.cueInDeterministicID(userID: userID, key: "field:linear")
            if fieldID == linearFieldID { return true }
        }
        return false
    }

    // MARK: - Smart views (AI / planner entry points)

    /// Not placed on any day — captured for later planning.
    var inboxTasks: [TaskItem] {
        tasks
            .filter { $0.isInboxed && $0.status != .archived }
            .sorted(by: prioritySort)
    }

    /// The executable pool for today. A task enters this list when the lightning
    /// action schedules it for today; Today timeline and formula fills consume it.
    var todayTasks: [TaskItem] {
        tasks
            .filter {
                $0.status != .archived &&
                ($0.isScheduledToday || $0.status == .active || $0.status == .paused)
            }
            .sorted(by: prioritySort)
    }

    var todayTaskIDSet: Set<UUID> {
        Set(tasks.lazy
            .filter {
                $0.status != .archived &&
                ($0.isScheduledToday || $0.status == .active || $0.status == .paused)
            }
            .map(\.id))
    }

    /// Future-scheduled tasks (grouped display handled by caller).
    var upcomingTasks: [TaskItem] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return tasks
            .filter {
                if $0.isCompleted || $0.status == .archived { return false }
                guard let d = $0.scheduledDate else { return false }
                return d >= Calendar.current.date(byAdding: .day, value: 1, to: startOfToday)!
            }
            .sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
    }

    /// Past-due and unfinished.
    var overdueTasks: [TaskItem] {
        tasks.filter(\.isOverdue).sorted(by: prioritySort)
    }

    /// Tasks completed since the start of today.
    var completedTodayTasks: [TaskItem] {
        tasks.filter { t in
            guard let c = t.completedAt else { return false }
            return Calendar.current.isDateInToday(c)
        }
    }

    /// All non-archived, non-completed tasks.
    var activeTasks: [TaskItem] {
        tasks.filter { $0.status != .archived && !$0.isCompleted }
    }

    // MARK: - Task CRUD

    func addTask(_ task: TaskItem) {
        AppLogger.shared.log("TasksStore: Adding task '\(task.title)'", category: .database)
        tasks.append(task)
        recordChanged(task: task)
        CueInSyncRuntimeBridge.shared.triggerImmediatePush(forTask: task)
    }

    func restoreTask(_ task: TaskItem, listKey: String? = nil) {
        guard !tasks.contains(where: { $0.id == task.id }) else { return }
        AppLogger.shared.log("TasksStore: Restoring task '\(task.title)'", category: .database)
        tasks.append(task)
        if let listKey {
            var order = taskListOrder[listKey] ?? []
            order.removeAll { $0 == task.id }
            order.insert(task.id, at: 0)
            taskListOrder[listKey] = order
        }
        recordChanged(task: task)
    }

    func updateTask(_ task: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        AppLogger.shared.log("TasksStore: Updating task '\(task.title)'", category: .database)
        var next = task
        next.updatedAt = Date()
        tasks[i] = next
        recordChanged(task: next)
        CueInSyncRuntimeBridge.shared.triggerImmediatePush(forTask: next)
    }

    /// Presents the Tasks-tab FAB undo affordance after a swipe (or checkbox popover) marks a task complete.
    func offerCompleteUndo(preCompletionSnapshot: TaskItem) {
        pendingCompleteUndoDismissTask?.cancel()
        pendingCompleteUndoSnapshot = preCompletionSnapshot
        let capturedID = preCompletionSnapshot.id
        pendingCompleteUndoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5.5))
            guard !Task.isCancelled else { return }
            if pendingCompleteUndoSnapshot?.id == capturedID {
                pendingCompleteUndoSnapshot = nil
            }
        }
    }

    /// Restores the snapshot from ``pendingCompleteUndoSnapshot`` and clears the pending undo.
    func consumeCompleteUndo() {
        guard let snap = pendingCompleteUndoSnapshot else { return }
        pendingCompleteUndoDismissTask?.cancel()
        pendingCompleteUndoDismissTask = nil
        pendingCompleteUndoSnapshot = nil
        updateTask(snap)
    }

    func clearCompleteUndo() {
        pendingCompleteUndoDismissTask?.cancel()
        pendingCompleteUndoDismissTask = nil
        pendingCompleteUndoSnapshot = nil
    }

    func deleteTask(_ id: UUID) {
        let deletedTask = tasks.first { $0.id == id }
        AppLogger.shared.log("TasksStore: Requesting deletion of task ID \(id) ('\(deletedTask?.title ?? "unknown")')", category: .database)
        if let deletedTask, deletedTask.isNotionImported {
            archiveImportedTaskLocally(deletedTask)
            CueInSyncRuntimeBridge.shared.triggerImmediatePush(forTask: deletedTask)
            return
        }
        tasks.removeAll { $0.id == id }
        for key in Array(taskListOrder.keys) {
            taskListOrder[key]?.removeAll { $0 == id }
        }
        if pendingCompleteUndoSnapshot?.id == id {
            clearCompleteUndo()
        }
        if let deletedTask {
            CueInSyncRuntimeBridge.shared.recordDeletedTask(deletedTask)
            CueInSyncRuntimeBridge.shared.triggerImmediatePush(forTask: deletedTask)
        }
    }

    private func archiveImportedTaskLocally(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        AppLogger.shared.log("TasksStore: Archiving imported Notion task '\(task.title)'", category: .database)
        tasks[index].status = .archived
        tasks[index].updatedAt = Date()
        for key in Array(taskListOrder.keys) {
            taskListOrder[key]?.removeAll { $0 == task.id }
        }
        if pendingCompleteUndoSnapshot?.id == task.id {
            clearCompleteUndo()
        }
        recordChanged(task: tasks[index])
    }

    // MARK: - Task list ordering (drag to reorder)

    /// Stable key for tasks scheduled on a given calendar day (upcoming groups).
    func upcomingListKey(day: Date) -> String {
        let t = Int(Calendar.current.startOfDay(for: day).timeIntervalSince1970)
        return "upcoming:\(t)"
    }

    /// Applies `prioritySort` unless a custom order exists for `listKey`.
    func orderedTasks(_ base: [TaskItem], listKey: String) -> [TaskItem] {
        guard let order = taskListOrder[listKey], !order.isEmpty else {
            return base.sorted(by: prioritySort)
        }
        let map = Dictionary(uniqueKeysWithValues: base.map { ($0.id, $0) })
        var seen = Set<UUID>()
        var result: [TaskItem] = []
        for id in order {
            guard let t = map[id] else { continue }
            result.append(t)
            seen.insert(id)
        }
        let tail = base.filter { !seen.contains($0.id) }.sorted(by: prioritySort)
        result.append(contentsOf: tail)
        return result
    }

    func moveTasks(listKey: String, orderedIDs: [UUID], from source: IndexSet, to destination: Int) {
        var ids = orderedIDs
        ids.move(fromOffsets: source, toOffset: destination)
        taskListOrder[listKey] = ids
    }

    func hasCustomTaskOrder(listKey: String) -> Bool {
        !(taskListOrder[listKey]?.isEmpty ?? true)
    }

    func setTaskOrder(listKey: String, orderedIDs: [UUID]) {
        taskListOrder[listKey] = orderedIDs
    }

    /// Clears a stored manual order so lists fall back to `prioritySort`.
    func clearTaskListOrder(listKey: String) {
        taskListOrder.removeValue(forKey: listKey)
    }

    func setTaskPriority(id: UUID, priority: TaskPriority) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        guard tasks[i].priority != priority else { return }
        AppLogger.shared.log("TasksStore: Setting task '\(tasks[i].title)' priority to \(priority.rawValue)", category: .database)
        tasks[i].priority = priority
        tasks[i].updatedAt = Date()
        recordChanged(task: tasks[i])
        CueInSyncRuntimeBridge.shared.triggerImmediatePush(forTask: tasks[i])
    }

    func setTaskStatus(id: UUID, status: TaskStatus) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        guard tasks[i].status != status else { return }
        AppLogger.shared.log("TasksStore: Setting task '\(tasks[i].title)' status to \(status.rawValue)", category: .database)
        switch status {
        case .inbox:
            tasks[i].scheduledDate = nil
            tasks[i].completedAt = nil
            tasks[i].status = .inbox
        case .scheduled:
            tasks[i].completedAt = nil
            tasks[i].status = .scheduled
        case .active:
            tasks[i].completedAt = nil
            tasks[i].status = .active
        case .paused:
            tasks[i].completedAt = nil
            tasks[i].status = .paused
        case .completed:
            tasks[i].status = .completed
            tasks[i].completedAt = tasks[i].completedAt ?? Date()
        case .archived:
            tasks[i].status = .archived
        }
        tasks[i].updatedAt = Date()
        recordChanged(task: tasks[i])
        CueInSyncRuntimeBridge.shared.triggerImmediatePush(forTask: tasks[i])
    }

    func toggleComplete(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let nextCompletedState = !tasks[i].isCompleted
        AppLogger.shared.log("TasksStore: Toggling completion of task '\(tasks[i].title)' to \(nextCompletedState)", category: .database)
        if tasks[i].isCompleted {
            tasks[i].status = tasks[i].scheduledDate == nil ? .inbox : .scheduled
            tasks[i].completedAt = nil
        } else {
            tasks[i].status = .completed
            tasks[i].completedAt = Date()
        }
        tasks[i].updatedAt = Date()
        recordChanged(task: tasks[i])
        CueInSyncRuntimeBridge.shared.triggerImmediatePush(forTask: tasks[i])
    }

    /// Sets completion without toggling (used when Today execution timeline updates a queued row).
    func setCompletion(_ id: UUID, completed: Bool) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        guard tasks[i].isCompleted != completed else { return }
        AppLogger.shared.log("TasksStore: Setting completion of task '\(tasks[i].title)' to \(completed)", category: .database)
        if completed {
            tasks[i].status = .completed
            tasks[i].completedAt = Date()
        } else {
            tasks[i].status = tasks[i].scheduledDate == nil ? .inbox : .scheduled
            tasks[i].completedAt = nil
        }
        tasks[i].updatedAt = Date()
        recordChanged(task: tasks[i])
        CueInSyncRuntimeBridge.shared.triggerImmediatePush(forTask: tasks[i])
    }

    func scheduleTask(_ id: UUID, on date: Date?) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        AppLogger.shared.log("TasksStore: Scheduling task '\(tasks[i].title)' on date \(date?.description ?? "nil")", category: .database)
        tasks[i].scheduledDate = date
        tasks[i].status = date == nil
            ? (tasks[i].isCompleted ? .completed : .inbox)
            : (tasks[i].isCompleted ? .completed : .scheduled)
        tasks[i].updatedAt = Date()
        recordChanged(task: tasks[i])
        CueInSyncRuntimeBridge.shared.triggerImmediatePush(forTask: tasks[i])
    }

    /// Today to-do row status menu — keeps tasks coherent with the execution pool.
    func setTodayTodoTaskStatus(id: UUID, status: TaskStatus) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let today = Calendar.current.startOfDay(for: Date())
        AppLogger.shared.log("TasksStore: Setting Today Todo status of task '\(tasks[i].title)' to \(status.rawValue)", category: .database)
        switch status {
        case .inbox:
            tasks[i].scheduledDate = nil
            tasks[i].completedAt = nil
            tasks[i].status = .inbox
        case .scheduled:
            tasks[i].scheduledDate = tasks[i].scheduledDate ?? today
            tasks[i].completedAt = nil
            tasks[i].status = .scheduled
        case .active:
            tasks[i].scheduledDate = tasks[i].scheduledDate ?? today
            tasks[i].completedAt = nil
            tasks[i].status = .active
        case .paused:
            tasks[i].scheduledDate = tasks[i].scheduledDate ?? today
            tasks[i].completedAt = nil
            tasks[i].status = .paused
        case .completed:
            tasks[i].status = .completed
            tasks[i].completedAt = tasks[i].completedAt ?? Date()
        case .archived:
            tasks[i].status = .archived
        }
        tasks[i].updatedAt = Date()
        recordChanged(task: tasks[i])
        CueInSyncRuntimeBridge.shared.triggerImmediatePush(forTask: tasks[i])
    }

    func toggleTodayTodoSubtask(taskID: UUID, subtaskID: UUID) {
        guard let ti = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        guard let si = tasks[ti].subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
        AppLogger.shared.log("TasksStore: Toggling Today subtask '\(tasks[ti].subtasks[si].title)' in '\(tasks[ti].title)'", category: .database)
        tasks[ti].subtasks[si].isCompleted.toggle()
        tasks[ti].updatedAt = Date()
        recordChanged(task: tasks[ti])
        CueInSyncRuntimeBridge.shared.triggerImmediatePush(forTask: tasks[ti])
    }

    // MARK: - Field CRUD

    func addField(_ f: Field) {
        AppLogger.shared.log("TasksStore: Adding field '\(f.name)'", category: .database)
        fields.append(f)
        recordChanged(field: f)
        CueInSyncRuntimeBridge.shared.triggerImmediatePush(forField: f)
    }

    func updateField(_ f: Field) {
        guard let i = fields.firstIndex(where: { $0.id == f.id }) else { return }
        AppLogger.shared.log("TasksStore: Updating field '\(f.name)'", category: .database)
        var next = f
        next.updatedAt = Date()
        fields[i] = next
        recordChanged(field: next)
        CueInSyncRuntimeBridge.shared.triggerImmediatePush(forField: next)
    }

    /// Removes the field, its projects, and clears `fieldID` on any orphaned tasks.
    func deleteField(_ id: UUID) {
        let deletedField = fields.first { $0.id == id }
        AppLogger.shared.log("TasksStore: Deleting field ID: \(id) ('\(deletedField?.name ?? "unknown")')", category: .database)
        let deletedProjects = projects.filter { $0.fieldID == id }
        let projIDs = deletedProjects.map(\.id)
        projects.removeAll { $0.fieldID == id }
        fields.removeAll { $0.id == id }
        let now = Date()
        var orphanedTasks: [TaskItem] = []
        for i in tasks.indices {
            var changed = false
            if tasks[i].fieldID == id { tasks[i].fieldID = nil; changed = true }
            if let pid = tasks[i].projectID, projIDs.contains(pid) {
                tasks[i].projectID = nil
                changed = true
            }
            if changed {
                tasks[i].updatedAt = now
                orphanedTasks.append(tasks[i])
            }
        }
        if let deletedField {
            CueInSyncRuntimeBridge.shared.recordDeletedField(deletedField)
            CueInSyncRuntimeBridge.shared.triggerImmediatePush(forField: deletedField)
        }
        for project in deletedProjects {
            CueInSyncRuntimeBridge.shared.recordDeletedProject(project)
        }
        for task in orphanedTasks {
            CueInSyncRuntimeBridge.shared.recordChangedTask(task)
        }
    }

    // MARK: - Project CRUD

    func addProject(_ p: Project) {
        AppLogger.shared.log("TasksStore: Adding project '\(p.name)'", category: .database)
        projects.append(p)
        recordChanged(project: p)
        CueInSyncRuntimeBridge.shared.triggerImmediatePush(forProject: p)
    }

    func updateProject(_ p: Project) {
        guard let i = projects.firstIndex(where: { $0.id == p.id }) else { return }
        AppLogger.shared.log("TasksStore: Updating project '\(p.name)'", category: .database)
        var next = p
        next.updatedAt = Date()
        projects[i] = next
        recordChanged(project: next)
        CueInSyncRuntimeBridge.shared.triggerImmediatePush(forProject: next)
    }

    /// Removes the project and clears `projectID` on its tasks (tasks stay on the field).
    func deleteProject(_ id: UUID) {
        let deletedProject = projects.first { $0.id == id }
        AppLogger.shared.log("TasksStore: Deleting project ID: \(id) ('\(deletedProject?.name ?? "unknown")')", category: .database)
        projects.removeAll { $0.id == id }
        let now = Date()
        var orphanedTasks: [TaskItem] = []
        for i in tasks.indices where tasks[i].projectID == id {
            tasks[i].projectID = nil
            tasks[i].updatedAt = now
            orphanedTasks.append(tasks[i])
        }
        if let deletedProject {
            CueInSyncRuntimeBridge.shared.recordDeletedProject(deletedProject)
            CueInSyncRuntimeBridge.shared.triggerImmediatePush(forProject: deletedProject)
        }
        for task in orphanedTasks {
            CueInSyncRuntimeBridge.shared.recordChangedTask(task)
        }
    }

    // MARK: - Progress helpers

    func progress(field: Field) -> (done: Int, total: Int) {
        let ts = tasks(in: field.id)
        return (ts.filter(\.isCompleted).count, ts.count)
    }

    func progress(project: Project) -> (done: Int, total: Int) {
        let ts = tasksInProject(project.id)
        return (ts.filter(\.isCompleted).count, ts.count)
    }

    // MARK: - AI planning snapshot

    /// JSON-serializable snapshot of the state relevant for AI day-planning.
    /// Shape is stable so it can be handed to an LLM as context.
    func planningSnapshot(for date: Date = Date()) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        func t(_ task: TaskItem) -> [String: Any] {
            var dict: [String: Any] = [
                "id": task.id.uuidString,
                "title": task.title,
                "priority": task.priority.rawValue,
                "status": task.status.rawValue,
                "plannedMinutes": task.plannedMinutes,
                "tags": task.tags,
                "savesToArchive": task.savesToArchive,
            ]
            if let executionType = task.executionType { dict["workType"] = executionType.rawValue }
            if let fid = task.fieldID, let f = field(fid) { dict["field"] = f.name }
            if let pid = task.projectID, let p = project(pid) { dict["project"] = p.name }
            if let s = task.scheduledDate { dict["startDate"] = iso.string(from: s) }
            if let d = task.dueDate { dict["dueDate"] = iso.string(from: d) }
            if task.recurrence != .none { dict["repeat"] = task.recurrence.rawValue }
            if !task.notes.isEmpty { dict["notes"] = task.notes }
            return dict
        }

        return [
            "date": iso.string(from: date),
            "fields": fields.map { [
                "id": $0.id.uuidString,
                "name": $0.name,
                "summary": $0.summary,
            ] as [String: Any] },
            "projects": projects.map { [
                "id": $0.id.uuidString,
                "name": $0.name,
                "fieldID": $0.fieldID.uuidString,
                "status": $0.status.rawValue,
            ] as [String: Any] },
            "today": todayTasks.map(t),
            "inbox": inboxTasks.map(t),
            "upcoming": upcomingTasks.prefix(30).map(t),
            "overdue": overdueTasks.map(t),
        ]
    }

    // MARK: - Helpers

    private func prioritySort(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.priority.sortWeight != b.priority.sortWeight {
            return a.priority.sortWeight < b.priority.sortWeight
        }
        return a.createdAt < b.createdAt
    }

    // MARK: - Seed
    //
    // Seeds the store from `MockDataService.sampleDay()` so the Tasks tab and
    // Today tab stay visually consistent during the transition. Each unique
    // `DayTask.field` / `.project` string becomes a real `Field` / `Project`
    // with a stable UUID. Going forward, the bridge will run the other
    // direction: Today should read `TasksStore.shared.todayTasks`.

    private static func makeSeed() -> (
        fields: [Field],
        projects: [Project],
        tasks: [TaskItem]
    ) {
        // Field defaults — matches color choices used elsewhere in the app.
        let fieldDefs: [(name: String, icon: String, hex: UInt, summary: String)] = [
            ("CueIn",      "app.fill",                      0x34C759, "Building the product"),
            ("Health",     "heart.fill",                    0x5BC6B9, "Body, recovery, movement"),
            ("Learning",   "graduationcap.fill",            0xA99BE0, "Study and skill-building"),
            ("Operations", "wrench.and.screwdriver.fill",   0xE2B253, "Admin, comms, meetings"),
        ]

        var fields: [Field] = []
        var fieldIDByName: [String: UUID] = [:]
        for def in fieldDefs {
            let f = Field(name: def.name, summary: def.summary, iconName: def.icon, colorHex: def.hex)
            fields.append(f)
            fieldIDByName[def.name] = f.id
        }

        // Collect unique projects from the mock day.
        let mockDay = MockDataService.sampleDay()
        var projectsByKey: [String: Project] = [:] // key = "field/project"
        for block in mockDay {
            for dayTask in block.tasks {
                guard
                    let fName = dayTask.field,
                    let pName = dayTask.project,
                    let fid = fieldIDByName[fName]
                else { continue }
                let key = "\(fName)/\(pName)"
                if projectsByKey[key] == nil {
                    projectsByKey[key] = Project(
                        name: pName,
                        iconName: "folder.fill",
                        fieldID: fid
                    )
                }
            }
        }
        let projects = projectsByKey.values.sorted { $0.name < $1.name }
        var projectIDByKey: [String: UUID] = [:]
        for p in projects {
            if let fname = fields.first(where: { $0.id == p.fieldID })?.name {
                projectIDByKey["\(fname)/\(p.name)"] = p.id
            }
        }

        // Build TaskItems from mock DayTasks; assign today's date so they land in "Today".
        var tasks: [TaskItem] = []
        let today = Calendar.current.startOfDay(for: Date())

        for block in mockDay {
            let exec: TaskExecutionType = {
                switch block.type {
                case .focus:   return .deepWork
                case .routine: return .multitask
                case .fixed:   return .deepWork
                case .mini:    return .multitask
                }
            }()
            let minutes = max(1, Int(block.endTime.timeIntervalSince(block.startTime) / 60))
            let perTaskMinutes = block.tasks.isEmpty ? minutes : max(5, minutes / block.tasks.count)

            for dayTask in block.tasks {
                let fid   = dayTask.field.flatMap { fieldIDByName[$0] }
                let pid: UUID? = {
                    guard let f = dayTask.field, let p = dayTask.project else { return nil }
                    return projectIDByKey["\(f)/\(p)"]
                }()

                let item = TaskItem(
                    title: dayTask.title,
                    fieldID: fid,
                    projectID: pid,
                    executionType: exec,
                    estimatedMinutes: perTaskMinutes,
                    priority: dayTask.isPrimary ? .high : .normal,
                    scheduledDate: today,
                    recurrence: dayTask.isRepeating ? .daily : .none,
                    status: dayTask.isCompleted ? .completed : .scheduled,
                    completedAt: dayTask.isCompleted ? Date() : nil
                )
                tasks.append(item)
            }
        }

        // Handful of extra demonstration tasks — one inbox, one overdue, one KPI, one upcoming.
        if let learningID = fieldIDByName["Learning"] {
            let systemsProj = projects.first { $0.name == "Systems" && $0.fieldID == learningID }?.id
            tasks.append(
                TaskItem(
                    title: "Draft architecture notes for v2",
                    notes: "Collect sketches + open questions before Monday review.",
                    fieldID: learningID,
                    projectID: systemsProj,
                    tags: ["research"],
                    executionType: .deepWork,
                    estimatedMinutes: 45,
                    priority: .high,
                    status: .inbox
                )
            )
            tasks.append(
                TaskItem(
                    title: "Read 30 min — System Design",
                    fieldID: learningID,
                    projectID: systemsProj,
                    tags: ["study"],
                    executionType: .deepWork,
                    estimatedMinutes: 30,
                    priority: .normal,
                    scheduledDate: today,
                    recurrence: .weekdays,
                    status: .scheduled
                )
            )
        }

        if let cueinID = fieldIDByName["CueIn"] {
            let iosProj = projects.first { $0.name == "iOS App" && $0.fieldID == cueinID }?.id
            tasks.append(
                TaskItem(
                    title: "Ship v1.2 release notes",
                    fieldID: cueinID,
                    projectID: iosProj,
                    tags: ["release"],
                    executionType: .multitask,
                    estimatedMinutes: 20,
                    priority: .high,
                    dueDate: Calendar.current.date(byAdding: .day, value: -1, to: today),
                    status: .inbox
                )
            )
            tasks.append(
                TaskItem(
                    title: "Plan Q2 roadmap with team",
                    fieldID: cueinID,
                    projectID: iosProj,
                    tags: ["planning"],
                    executionType: .deepWork,
                    estimatedMinutes: 90,
                    priority: .high,
                    scheduledDate: Calendar.current.date(byAdding: .day, value: 2, to: today),
                    status: .scheduled
                )
            )
        }

        if let healthID = fieldIDByName["Health"] {
            let trainingProj = projects.first { $0.name == "Training" && $0.fieldID == healthID }?.id
            tasks.append(
                TaskItem(
                    title: "Hit 10k steps",
                    fieldID: healthID,
                    projectID: trainingProj,
                    tags: ["steps"],
                    executionType: .shallowWork,
                    estimatedMinutes: 20,
                    priority: .normal,
                    scheduledDate: today,
                    recurrence: .daily,
                    status: .scheduled
                )
            )
        }

        return (fields, projects, tasks)
    }

    /// Re-applies the bundled demo dataset (aligned with ``MockDataService``).
    func replaceWithGimmickSeed() {
        let seed = Self.makeSeed()
        fields = seed.fields
        projects = seed.projects
        tasks = seed.tasks
        taskListOrder = [:]
        if !suppressSyncRecording {
            CueInSyncRuntimeBridge.shared.recordWorkspaceSnapshot()
        }
    }

    /// Clears fields, projects, tasks, and manual list ordering.
    func clearAllTasksData() {
        for field in fields {
            CueInSyncRuntimeBridge.shared.recordDeletedField(field)
        }
        for project in projects {
            CueInSyncRuntimeBridge.shared.recordDeletedProject(project)
        }
        for task in tasks {
            CueInSyncRuntimeBridge.shared.recordDeletedTask(task)
        }
        fields = []
        projects = []
        tasks = []
        taskListOrder = [:]
    }

    /// Applies a server-pulled snapshot to memory. Preserves user-only state that
    /// isn't synced yet (currently `taskListOrder`) so a remote pull doesn't lose
    /// drag-reordering on the device that hasn't pushed it.
    func replaceFromSync(fields syncedFields: [Field], projects syncedProjects: [Project], tasks syncedTasks: [TaskItem]) {
        UserDefaults.standard.set(true, forKey: CueInAppDataKeys.gimmickDemoRemoved)
        suppressSyncRecording = true
        fields = syncedFields
        projects = syncedProjects
        tasks = syncedTasks
        let validIDs = Set(syncedTasks.map(\.id))
        for key in Array(taskListOrder.keys) {
            taskListOrder[key] = taskListOrder[key]?.filter { validIDs.contains($0) }
            if taskListOrder[key]?.isEmpty == true {
                taskListOrder.removeValue(forKey: key)
            }
        }
        suppressSyncRecording = false
    }

    // MARK: - Conflict bookkeeping

    /// Replaces conflicts for `source` with the freshly-returned set. Tasks that
    /// the server *didn't* re-flag are considered resolved and dropped from the
    /// local map. Conflicts from the *other* integration are left untouched so
    /// a Linear push doesn't accidentally clear pending Notion conflicts.
    func applyServerConflicts(_ remote: [TaskConflict], source: TaskConflict.Source) {
        let nextIDs = Set(remote.map(\.cueInID))
        for (id, existing) in taskConflicts where existing.source == source {
            if !nextIDs.contains(id) {
                taskConflicts.removeValue(forKey: id)
            }
        }
        for conflict in remote {
            // Keep the original observedAt if we already had this conflict open;
            // otherwise stamp it now. Stable observedAt prevents banner flicker.
            if let existing = taskConflicts[conflict.cueInID], existing.source == source {
                taskConflicts[conflict.cueInID] = TaskConflict(
                    cueInID: conflict.cueInID,
                    source: conflict.source,
                    remoteUpdatedAt: conflict.remoteUpdatedAt,
                    localUpdatedAt: conflict.localUpdatedAt,
                    remoteSnapshot: conflict.remoteSnapshot,
                    observedAt: existing.observedAt
                )
            } else {
                taskConflicts[conflict.cueInID] = conflict
            }
        }
    }

    func clearConflict(for taskID: UUID) {
        taskConflicts.removeValue(forKey: taskID)
    }

    /// Bumps the local task's `updatedAt` so the next push wins the timestamp
    /// race even after the user picked "Keep mine". The integration store also
    /// passes `force_overwrite_task_ids` to bypass the server-side check.
    func markKeptLocalForConflict(taskID: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[i].updatedAt = Date()
        recordChanged(task: tasks[i])
    }

    // MARK: - Sync recording helpers

    private func recordChanged(task: TaskItem) {
        guard !suppressSyncRecording else { return }
        CueInSyncRuntimeBridge.shared.recordChangedTask(task)
    }

    private func recordChanged(project: Project) {
        guard !suppressSyncRecording else { return }
        CueInSyncRuntimeBridge.shared.recordChangedProject(project)
    }

    private func recordChanged(field: Field) {
        guard !suppressSyncRecording else { return }
        CueInSyncRuntimeBridge.shared.recordChangedField(field)
    }
}
