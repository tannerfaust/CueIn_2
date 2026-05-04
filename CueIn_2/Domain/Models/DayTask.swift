import Foundation

// MARK: - DayTask
/// A single task unit that lives inside a DayBlock.

struct DayTask: Identifiable, Codable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var isPrimary: Bool
    var isRepeating: Bool
    /// The `DayBlock` id this task originated from in another day engine view
    /// (used to mirror completion across schedule and timeline modes).
    var sourceExecutionBlockID: UUID?
    /// The `ExecutionTaskCard` id (or source task id) this DayTask represents
    /// on the Timeline. Used for bidirectional completion sync.
    var sourceExecutionTaskID: UUID?
    /// Strong link back to a `TasksStore.TaskItem` — set when the row comes
    /// from the execution pool (e.g. via a Schedule fill block). Lets us
    /// resolve the pool card regardless of transient card ids.
    var plannerTaskItemID: UUID?
    var field: String?
    var project: String?
    var folder: String?

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        isPrimary: Bool = false,
        isRepeating: Bool = false,
        sourceExecutionBlockID: UUID? = nil,
        sourceExecutionTaskID: UUID? = nil,
        plannerTaskItemID: UUID? = nil,
        field: String? = nil,
        project: String? = nil,
        folder: String? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.isPrimary = isPrimary
        self.isRepeating = isRepeating
        self.sourceExecutionBlockID = sourceExecutionBlockID
        self.sourceExecutionTaskID = sourceExecutionTaskID
        self.plannerTaskItemID = plannerTaskItemID
        self.field = field
        self.project = project
        self.folder = folder
    }
}
