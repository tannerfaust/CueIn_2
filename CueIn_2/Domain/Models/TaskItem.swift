import Foundation

// MARK: - TaskItem
/// The atomic unit of work. Lives in `TasksStore` and is the source of truth
/// for everything in the Tasks module. Day scheduling is a function of
/// `scheduledDate` + `status`; AI planners consume the enums as structured signals.

struct TaskItem: Identifiable, Codable, Hashable {

    // MARK: Identity
    let id: UUID

    // MARK: Content
    var title: String
    var notes: String

    // MARK: Organization
    var fieldID: UUID?
    var projectID: UUID?
    var tags: [String]

    // MARK: Execution model
    var executionType: TaskExecutionType?
    var estimatedMinutes: Int?
    var priority: TaskPriority

    // MARK: Scheduling
    var scheduledDate: Date?
    var dueDate: Date?
    var recurrence: TaskRecurrence

    // MARK: Lifecycle
    var status: TaskStatus
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var subtasks: [TaskSubtask]
    /// Kept by default so archived/completed task history remains available to future planning assistants.
    var savesToArchive: Bool
    var externalSource: String?

    // MARK: Init

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        fieldID: UUID? = nil,
        projectID: UUID? = nil,
        tags: [String] = [],
        executionType: TaskExecutionType? = nil,
        estimatedMinutes: Int? = nil,
        priority: TaskPriority = .normal,
        scheduledDate: Date? = nil,
        dueDate: Date? = nil,
        recurrence: TaskRecurrence = .none,
        status: TaskStatus = .inbox,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        subtasks: [TaskSubtask] = [],
        savesToArchive: Bool = true,
        externalSource: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.fieldID = fieldID
        self.projectID = projectID
        self.tags = tags
        self.executionType = executionType
        self.estimatedMinutes = estimatedMinutes
        self.priority = priority
        self.scheduledDate = scheduledDate
        self.dueDate = dueDate
        self.recurrence = recurrence
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.subtasks = subtasks
        self.savesToArchive = savesToArchive
        self.externalSource = externalSource
    }

    // MARK: Derived state

    var isCompleted: Bool { status == .completed }

    var isScheduledToday: Bool {
        guard let d = scheduledDate else { return false }
        return Calendar.current.isDateInToday(d)
    }

    var isOverdue: Bool {
        guard let due = dueDate, !isCompleted else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }

    var isInboxed: Bool {
        status == .inbox && scheduledDate == nil
    }

    var isNotionImported: Bool {
        externalSource?.localizedCaseInsensitiveCompare("notion") == .orderedSame
    }

    /// Minutes to reflect this task on a plan — estimate or a conservative fallback.
    var plannedMinutes: Int {
        if let m = estimatedMinutes { return m }
        switch executionType {
        case .deepWork:  return 45
        case .shallowWork: return 25
        case .multitask: return 15
        case nil: return 30
        }
    }
}

// MARK: - TaskSubtask

struct TaskSubtask: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}
