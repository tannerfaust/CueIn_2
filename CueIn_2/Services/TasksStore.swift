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

    // MARK: State (published)

    var fields: [Field] = []
    var projects: [Project] = []
    var tasks: [TaskItem] = []

    /// Per-list manual ordering (like iOS notification stacks). Keys are owned by callers
    /// (`"inbox"`, `"today:field:\(uuid)"`, `"upcoming:\(dayStart)"`, etc.). Unknown IDs are ignored;
    /// tasks missing from a stored order are appended using `prioritySort`.
    var taskListOrder: [String: [UUID]] = [:]

    // MARK: Init

    private init() {
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
        tasks.append(task)
        recordSyncSnapshot()
    }

    func restoreTask(_ task: TaskItem, listKey: String? = nil) {
        guard !tasks.contains(where: { $0.id == task.id }) else { return }
        tasks.append(task)
        if let listKey {
            var order = taskListOrder[listKey] ?? []
            order.removeAll { $0 == task.id }
            order.insert(task.id, at: 0)
            taskListOrder[listKey] = order
        }
        recordSyncSnapshot()
    }

    func updateTask(_ task: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var next = task
        next.updatedAt = Date()
        tasks[i] = next
        recordSyncSnapshot()
    }

    func deleteTask(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        for key in Array(taskListOrder.keys) {
            taskListOrder[key]?.removeAll { $0 == id }
        }
        recordSyncSnapshot()
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
        tasks[i].priority = priority
        tasks[i].updatedAt = Date()
        recordSyncSnapshot()
    }

    func toggleComplete(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        if tasks[i].isCompleted {
            tasks[i].status = tasks[i].scheduledDate == nil ? .inbox : .scheduled
            tasks[i].completedAt = nil
        } else {
            tasks[i].status = .completed
            tasks[i].completedAt = Date()
        }
        tasks[i].updatedAt = Date()
        recordSyncSnapshot()
    }

    /// Sets completion without toggling (used when Today execution timeline updates a queued row).
    func setCompletion(_ id: UUID, completed: Bool) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        guard tasks[i].isCompleted != completed else { return }
        if completed {
            tasks[i].status = .completed
            tasks[i].completedAt = Date()
        } else {
            tasks[i].status = tasks[i].scheduledDate == nil ? .inbox : .scheduled
            tasks[i].completedAt = nil
        }
        tasks[i].updatedAt = Date()
        recordSyncSnapshot()
    }

    func scheduleTask(_ id: UUID, on date: Date?) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].scheduledDate = date
        tasks[i].status = date == nil
            ? (tasks[i].isCompleted ? .completed : .inbox)
            : (tasks[i].isCompleted ? .completed : .scheduled)
        tasks[i].updatedAt = Date()
        recordSyncSnapshot()
    }

    /// Today to-do row status menu — keeps tasks coherent with the execution pool.
    func setTodayTodoTaskStatus(id: UUID, status: TaskStatus) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let today = Calendar.current.startOfDay(for: Date())
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
        recordSyncSnapshot()
    }

    func toggleTodayTodoSubtask(taskID: UUID, subtaskID: UUID) {
        guard let ti = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        guard let si = tasks[ti].subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
        tasks[ti].subtasks[si].isCompleted.toggle()
        tasks[ti].updatedAt = Date()
        recordSyncSnapshot()
    }

    // MARK: - Field CRUD

    func addField(_ f: Field) {
        fields.append(f)
        recordSyncSnapshot()
    }

    func updateField(_ f: Field) {
        guard let i = fields.firstIndex(where: { $0.id == f.id }) else { return }
        fields[i] = f
        recordSyncSnapshot()
    }

    /// Removes the field, its projects, and clears `fieldID` on any orphaned tasks.
    func deleteField(_ id: UUID) {
        let projIDs = projects.filter { $0.fieldID == id }.map(\.id)
        projects.removeAll { $0.fieldID == id }
        fields.removeAll { $0.id == id }
        for i in tasks.indices {
            if tasks[i].fieldID == id { tasks[i].fieldID = nil }
            if let pid = tasks[i].projectID, projIDs.contains(pid) {
                tasks[i].projectID = nil
            }
        }
        recordSyncSnapshot()
    }

    // MARK: - Project CRUD

    func addProject(_ p: Project) {
        projects.append(p)
        recordSyncSnapshot()
    }

    func updateProject(_ p: Project) {
        guard let i = projects.firstIndex(where: { $0.id == p.id }) else { return }
        projects[i] = p
        recordSyncSnapshot()
    }

    /// Removes the project and clears `projectID` on its tasks (tasks stay on the field).
    func deleteProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        for i in tasks.indices where tasks[i].projectID == id {
            tasks[i].projectID = nil
        }
        recordSyncSnapshot()
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
        recordSyncSnapshot()
    }

    /// Clears fields, projects, tasks, and manual list ordering.
    func clearAllTasksData() {
        fields = []
        projects = []
        tasks = []
        taskListOrder = [:]
        recordSyncSnapshot()
    }

    private func recordSyncSnapshot() {
        CueInSyncRuntimeBridge.shared.recordTasksSnapshot()
    }
}
