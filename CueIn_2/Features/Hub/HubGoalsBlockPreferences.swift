import Foundation
import SwiftUI

// MARK: - Hub Goals block (Hub tab only)

/// User defaults for the Goals hero on ``HubView``. Keys are namespaced under `cuein.hub.goalsBlock.*`.
enum HubGoalsBlockPreferences {

    enum Keys {
        static let focusMode = "cuein.hub.goalsBlock.focusMode"
        static let density = "cuein.hub.goalsBlock.density"
        static let showSectionSubtitle = "cuein.hub.goalsBlock.showSectionSubtitle"
        static let showActiveCount = "cuein.hub.goalsBlock.showActiveCount"
        static let showGoalDescription = "cuein.hub.goalsBlock.showGoalDescription"
        static let showSubgoalCounts = "cuein.hub.goalsBlock.showSubgoalCounts"
        static let showProgressBar = "cuein.hub.goalsBlock.showProgressBar"
        static let showProgressRing = "cuein.hub.goalsBlock.showProgressRing"
        static let showPercentage = "cuein.hub.goalsBlock.showPercentage"
        static let showNextAction = "cuein.hub.goalsBlock.showNextAction"
        static let showStageTitle = "cuein.hub.goalsBlock.showStageTitle"
        static let showDates = "cuein.hub.goalsBlock.showDates"
        static let stagesVisualization = "cuein.hub.goalsBlock.stagesVisualization"
        static let cardStyle = "cuein.hub.goalsBlock.cardStyle"
        static let showAccentRail = "cuein.hub.goalsBlock.showAccentRail"
    }

    enum Density: String, CaseIterable, Identifiable {
        case compact
        case comfortable

        var id: String { rawValue }

        var menuTitle: String {
            switch self {
            case .compact: return "Compact"
            case .comfortable: return "Comfortable"
            }
        }
    }

    enum StagesVisualization: String, CaseIterable, Identifiable {
        case off
        case minimalBar
        case expandedList

        var id: String { rawValue }

        var menuTitle: String {
            switch self {
            case .off: return "Off"
            case .minimalBar: return "Minimal bar"
            case .expandedList: return "Expanded list"
            }
        }
    }

    enum CardStyle: String, CaseIterable, Identifiable {
        case surface
        case glass

        var id: String { rawValue }

        var menuTitle: String {
            switch self {
            case .surface: return "Solid card"
            case .glass: return "Glass card"
            }
        }
    }

    static func resetToDefaults(using defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: Keys.focusMode)
        defaults.set(Density.comfortable.rawValue, forKey: Keys.density)
        defaults.set(false, forKey: Keys.showSectionSubtitle)
        defaults.set(true, forKey: Keys.showActiveCount)
        defaults.set(false, forKey: Keys.showGoalDescription)
        defaults.set(false, forKey: Keys.showSubgoalCounts)
        defaults.set(true, forKey: Keys.showProgressBar)
        defaults.set(false, forKey: Keys.showProgressRing)
        defaults.set(true, forKey: Keys.showPercentage)
        defaults.set(false, forKey: Keys.showNextAction)
        defaults.set(false, forKey: Keys.showStageTitle)
        defaults.set(false, forKey: Keys.showDates)
        defaults.set(StagesVisualization.off.rawValue, forKey: Keys.stagesVisualization)
        defaults.set(CardStyle.surface.rawValue, forKey: Keys.cardStyle)
        defaults.set(true, forKey: Keys.showAccentRail)
    }
}
