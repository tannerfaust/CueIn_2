import Foundation

// MARK: - TaskLeadPresentation
/// Secondary task-led views inside Today.

enum TaskLeadPresentation: String, CaseIterable, Identifiable, Codable {
    case tasksOnly
    case tasksWithBlocks

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tasksOnly: return "Tasks"
        case .tasksWithBlocks: return "Blocks"
        }
    }
}
