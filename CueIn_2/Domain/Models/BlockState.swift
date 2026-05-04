import Foundation

// MARK: - BlockState
/// Represents the execution state of a day block.

enum BlockState: String, Codable {
    case upcoming
    case active
    case completed
    case skipped
}
