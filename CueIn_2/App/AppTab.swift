import SwiftUI

// MARK: - AppTab
/// Primary destinations that can appear in CueIn's bottom navigation.

enum AppTab: String, CaseIterable, Identifiable {
    /// Former formula / day-schedule surface ("Algorithm").
    case schedule
    /// Unified task-led day (To-do vs Timeline follows ``TodayDisplayPreferences.taskLedViewMode``).
    case taskLed
    case tasks
    case projects
    case stats
    case goals
    /// Things you are choosing **not** to do (local list; not tasks).
    case antiTodo
    /// Personal measures and logging (quantified self); also opened from Hub.
    case quantifiedSelf
    /// Focus timer; opened from Hub or pinned in the navbar.
    case pomodoro
    /// Ambient focus audio; opened from Hub or pinned in the navbar.
    case sounds
    case hub
    case more

    var id: String { rawValue }

    static let storageKey = "cuein.app.nav.tabs.v1"
    static let maximumVisibleTabs = 5
    /// Shows both day-engine tabs plus Tasks, Stats, and Hub (five slots).
    static let defaultTabs: [AppTab] = [.schedule, .taskLed, .tasks, .stats, .hub]

    static var editableTabs: [AppTab] {
        [.schedule, .taskLed, .tasks, .projects, .stats, .goals, .antiTodo, .quantifiedSelf, .pomodoro, .sounds, .more, .hub]
    }

    /// Maps legacy persisted ids (`timeline`, `todo`) onto ``taskLed``.
    static func migrateLegacyTabToken(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "timeline", "todo": return AppTab.taskLed.rawValue
        case "focus": return AppTab.pomodoro.rawValue
        default: return raw
        }
    }

    static func storedTabs(from rawValue: String) -> [AppTab] {
        let tokens = rawValue.split(separator: ",").map { migrateLegacyTabToken(String($0)) }
        return sanitize(tokens.compactMap { AppTab(rawValue: $0) })
    }

    static func storageValue(for tabs: [AppTab]) -> String {
        sanitize(tabs).map(\.rawValue).joined(separator: ",")
    }

    static func sanitize(_ tabs: [AppTab]) -> [AppTab] {
        var result: [AppTab] = []
        for tab in tabs where !result.contains(tab) {
            result.append(tab)
        }

        if result.isEmpty {
            result = defaultTabs
        }

        if !result.contains(.hub) {
            result.append(.hub)
        }

        if result.count > maximumVisibleTabs {
            if let hubIndex = result.firstIndex(of: .hub), hubIndex >= maximumVisibleTabs {
                result.remove(at: hubIndex)
                result.insert(.hub, at: maximumVisibleTabs - 1)
            }
            result = Array(result.prefix(maximumVisibleTabs))
            if !result.contains(.hub) {
                result[result.count - 1] = .hub
            }
        }

        return result
    }

    var label: String {
        switch self {
        case .schedule: return "Algorithm"
        /// Fallback only; the tab bar reads ``TodayDisplayPreferences.TaskLedViewMode`` for the live title.
        case .taskLed: return "Timeline"
        case .tasks: return "Tasks"
        case .projects: return "Projects"
        case .stats: return "Stats"
        case .goals: return "Goals"
        case .antiTodo: return "Anti To‑do"
        case .quantifiedSelf: return "Measures"
        case .pomodoro: return "Timer"
        case .sounds: return "Sounds"
        case .hub: return "Hub"
        case .more: return "More"
        }
    }

    /// Short titles for the navbar customization list (static; task-led tab covers both To-do and Timeline).
    var rearrangementPickerLabel: String {
        switch self {
        case .schedule: return "Algorithm"
        case .taskLed: return "To-do / Timeline"
        default: return label
        }
    }

    var icon: String {
        switch self {
        case .schedule: return "arrow.triangle.branch"
        case .taskLed: return "calendar.day.timeline.left"
        case .tasks: return "checkmark.circle.fill"
        case .projects: return "folder.fill"
        case .stats: return "chart.bar.fill"
        case .goals: return "target"
        case .antiTodo: return "slash.circle.fill"
        case .quantifiedSelf: return "chart.xyaxis.line"
        case .pomodoro: return "timer"
        case .sounds: return "waveform"
        case .hub: return "square.grid.2x2.fill"
        case .more: return "ellipsis.circle.fill"
        }
    }

    var iconInactive: String {
        switch self {
        case .schedule: return "arrow.triangle.branch"
        case .taskLed: return "calendar.day.timeline.left"
        case .tasks: return "checkmark.circle"
        case .projects: return "folder"
        case .stats: return "chart.bar"
        case .goals: return "target"
        case .antiTodo: return "slash.circle"
        case .quantifiedSelf: return "chart.line.uptrend.xyaxis"
        case .pomodoro: return "timer"
        case .sounds: return "waveform"
        case .hub: return "square.grid.2x2"
        case .more: return "ellipsis.circle"
        }
    }

    var preferredTodayMode: (dayEngine: DayEngineMode, taskLedViewMode: TodayDisplayPreferences.TaskLedViewMode?)? {
        switch self {
        case .schedule:
            return (.formulaBased, nil)
        case .taskLed:
            return (.taskLed, nil)
        default:
            return nil
        }
    }

    var canRemoveFromNavigation: Bool {
        self != .hub
    }
}
