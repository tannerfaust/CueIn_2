import Foundation

// MARK: - TaskLeadTaskItem

struct TaskLeadTaskItem: Identifiable {
    let id: UUID
    let blockID: UUID
    let blockTitle: String
    let blockTypeLabel: String
    let blockState: BlockState
    let task: DayTask
    let order: Int

    var isCompleted: Bool { task.isCompleted }
}

// MARK: - TaskLeadTaskSection

struct TaskLeadTaskSection: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let items: [TaskLeadTaskItem]
}
