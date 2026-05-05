import SwiftUI

// MARK: - TaskAttributes
/// All the small, machine-readable attributes that describe a `TaskItem`.
/// Kept in one file because they are atomic enums with no internal dependencies;
/// designed to be Codable + Identifiable so AI planners and persistence layers
/// can round-trip tasks as JSON without loss.

// MARK: - TaskExecutionType
/// How the task wants to be executed. Drives block-type matching during planning.

enum TaskExecutionType: String, Codable, CaseIterable, Identifiable, Hashable {
    /// Single-threaded, focus-heavy work. Best placed inside a Focus block.
    case deepWork
    /// Lightweight solo work that does not require a deep focus block.
    case shallowWork
    /// Light work that can run in parallel with other tasks (emails, admin).
    case multitask

    var id: String { rawValue }

    var label: String {
        switch self {
        case .deepWork:  return "Deep Work"
        case .shallowWork: return "Shallow Work"
        case .multitask: return "Multitasking"
        }
    }

    var shortLabel: String {
        switch self {
        case .deepWork:  return "Deep"
        case .shallowWork: return "Shallow"
        case .multitask: return "Multi"
        }
    }

    var icon: String {
        switch self {
        case .deepWork:  return "brain.head.profile"
        case .shallowWork: return "text.line.first.and.arrowtriangle.forward"
        case .multitask: return "square.stack.3d.up.fill"
        }
    }

    var summary: String {
        switch self {
        case .deepWork:  return "Single-threaded focus. Best inside a focus block."
        case .shallowWork: return "Clear, lightweight execution. Good between larger blocks."
        case .multitask: return "Light tasks that can run in parallel."
        }
    }

    var color: Color {
        switch self {
        case .deepWork:  return CueInColors.accentFocus
        case .shallowWork: return CueInColors.textSecondary
        case .multitask: return CueInColors.accentRoutine
        }
}
}

// MARK: - TaskPriority

enum TaskPriority: String, Codable, CaseIterable, Identifiable, Hashable {
    case normal, high, urgent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .high:   return "High"
        case .urgent: return "Urgent"
        }
    }

    var shortLabel: String {
        switch self {
        case .normal: return "Normal"
        case .high:   return "High"
        case .urgent: return "Urgent"
        }
    }

    var icon: String {
        switch self {
        case .normal: return "minus.circle"
        case .high:   return "flame.fill"
        case .urgent: return "flame.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .normal: return CueInColors.textSecondary
        case .high:   return CueInColors.accentFixed
        case .urgent: return CueInColors.danger
        }
    }

    /// Lower is more important — use for sorting.
    var sortWeight: Int {
        switch self {
        case .urgent: return 0
        case .high:   return 1
        case .normal: return 2
        }
    }
}

// MARK: - TaskStatus

enum TaskStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    /// Inbox / backlog — not on today’s To-do until queued again (no `scheduledDate` for today).
    case inbox
    /// Queued — on the calendar day and ready to run (Linear “Todo”).
    case scheduled
    /// Doing — actively in progress (Linear “In Progress”).
    case active
    /// Still on today’s plan but intentionally stopped (distinct from Waiting / Done).
    case paused
    case completed
    case archived

    var id: String { rawValue }

    /// Linear-inspired workflow names (distinct from Linear’s exact copy).
    var label: String {
        switch self {
        case .inbox:      return "Waiting"
        case .scheduled:  return "On execution"
        case .active:     return "In progress"
        case .paused:     return "Paused"
        case .completed:  return "Done"
        case .archived:   return "Archived"
        }
    }

    var icon: String {
        switch self {
        case .inbox:      return "circle.dashed"
        case .scheduled:  return "circle"
        case .active:     return "play.circle.fill"
        case .paused:     return "pause.circle.fill"
        case .completed:  return "checkmark.circle.fill"
        case .archived:   return "archivebox.fill"
        }
    }

    var color: Color {
        switch self {
        case .inbox:      return CueInColors.textTertiary
        case .scheduled: return CueInColors.textSecondary
        case .active:     return CueInColors.accentFocus
        case .paused:     return CueInColors.warning
        case .completed:  return CueInColors.success
        case .archived:   return CueInColors.textTertiary
        }
    }

    /// Open workflow states for Today’s execution pool (excluding Done / Archived).
    static var executionPoolOpenStatuses: [TaskStatus] {
        [.inbox, .scheduled, .active, .paused]
    }

    /// Full picker order (shared popover everywhere).
    static var statusPickerOrdering: [TaskStatus] {
        [.inbox, .scheduled, .active, .paused, .completed, .archived]
    }

    /// Title when moving out of Done back into an open state.
    func reopenFromDoneMenuTitle() -> String {
        switch self {
        case .inbox:      return "Re-open as Waiting"
        case .scheduled:  return "Re-open on execution"
        case .active:     return "Re-open in progress"
        case .paused:     return "Re-open paused"
        case .completed:  return "Done"
        case .archived:   return "Archived"
        }
    }
}

// MARK: - TaskRecurrence

enum TaskRecurrence: String, Codable, CaseIterable, Identifiable, Hashable {
    case none
    case daily
    case weekdays
    case weekends
    case weekly
    case monthly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:     return "Doesn't repeat"
        case .daily:    return "Every day"
        case .weekdays: return "Weekdays"
        case .weekends: return "Weekends"
        case .weekly:   return "Weekly"
        case .monthly:  return "Monthly"
        }
    }

    var shortLabel: String {
        switch self {
        case .none:     return "Once"
        case .daily:    return "Daily"
        case .weekdays: return "Weekdays"
        case .weekends: return "Weekends"
        case .weekly:   return "Weekly"
        case .monthly:  return "Monthly"
        }
    }

    var icon: String { "arrow.clockwise" }
}
