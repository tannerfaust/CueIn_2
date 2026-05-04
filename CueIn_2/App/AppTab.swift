import SwiftUI

// MARK: - AppTab
/// The four primary navigation tabs in CueIn.

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case tasks
    case stats
    case hub

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .tasks: return "Tasks"
        case .stats: return "Stats"
        case .hub:   return "Hub"
        }
    }

    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .tasks: return "checkmark.circle.fill"
        case .stats: return "chart.bar.fill"
        case .hub:   return "square.grid.2x2.fill"
        }
    }

    var iconInactive: String {
        switch self {
        case .today: return "sun.max"
        case .tasks: return "checkmark.circle"
        case .stats: return "chart.bar"
        case .hub:   return "square.grid.2x2"
        }
    }
}

// MARK: - TodayTabBarPresentation
/// First shell tab label + icons mirror the active Today engine (schedule vs task-led) and task-led sub-mode.

struct TodayTabBarPresentation: Equatable {
    var title: String
    var icon: String
    var iconInactive: String

    static func resolved(
        dayEngine: DayEngineMode,
        taskLedViewMode: TodayDisplayPreferences.TaskLedViewMode
    ) -> Self {
        switch dayEngine {
        case .formulaBased:
            Self(title: "Schedule", icon: "calendar.circle.fill", iconInactive: "calendar.circle")
        case .taskLed:
            switch taskLedViewMode {
            case .todo:
                Self(title: "To do", icon: "checklist", iconInactive: "checklist")
            case .timeline:
                Self(
                    title: "Timeline",
                    icon: "calendar.day.timeline.left",
                    iconInactive: "calendar.day.timeline.left"
                )
            }
        }
    }
}
