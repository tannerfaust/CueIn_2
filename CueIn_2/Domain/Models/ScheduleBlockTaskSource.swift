import Foundation

// MARK: - ScheduleBlockTaskSource
/// Defines where a Schedule block gets its tasks from.

enum ScheduleBlockTaskSource: String, CaseIterable, Codable {
    case templateTasks
    case executionFill
    /// Block is time/structure only — no checklist and no pool fill.
    case noTasks
}
