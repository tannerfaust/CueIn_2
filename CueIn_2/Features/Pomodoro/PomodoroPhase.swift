import Foundation

// MARK: - PomodoroPhase

enum PomodoroPhase: String, CaseIterable, Codable, Sendable {
    case work
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .work: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }

    var accessibilitySummary: String {
        switch self {
        case .work: return "Focus interval"
        case .shortBreak: return "Short rest"
        case .longBreak: return "Long rest"
        }
    }
}
