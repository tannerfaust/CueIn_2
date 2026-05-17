import Foundation
import Observation
import SwiftUI

// MARK: - DevNotebookContext

/// Live shell location for dev notebook captures (tab + optional screen title).
@MainActor
@Observable
final class DevNotebookContext {
    static let shared = DevNotebookContext()

    var selectedTab: AppTab = .taskLed
    var screenLabel: String?
    /// True while Hub presents the full-screen Dev notebook (hide shell floating capture to avoid stacked sheets).
    var hubNotebookSheetPresented = false

    private init() {}

    /// Builds module + context strings from the current tab, optional screen label, and persisted Today prefs.
    func makeSnapshot() -> (moduleLabel: String, contextLine: String) {
        let moduleLabel = captureModuleLabel

        var segments: [String] = []

        if selectedTab.preferredTodayMode != nil {
            let modeRaw = UserDefaults.standard.string(forKey: DayEngineMode.storageKey) ?? DayEngineMode.taskLed.rawValue
            let engine = DayEngineMode(rawValue: modeRaw) ?? .taskLed
            switch engine {
            case .formulaBased:
                segments.append("Blocks")
            case .taskLed:
                let vmRaw = UserDefaults.standard.string(forKey: TodayDisplayPreferences.taskLedViewMode)
                    ?? TodayDisplayPreferences.TaskLedViewMode.timeline.rawValue
                let vm = TodayDisplayPreferences.TaskLedViewMode(rawValue: vmRaw) ?? .timeline
                segments.append(vm.title)
            }
        } else {
            segments.append(moduleLabel)
        }

        if let s = screenLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            segments.append(s)
        }

        let deduped = segments.reduce(into: [String]()) { acc, s in
            if acc.last != s { acc.append(s) }
        }

        return (moduleLabel, deduped.joined(separator: " · "))
    }

    private var captureModuleLabel: String {
        switch selectedTab {
        case .schedule:
            return "Blocks"
        case .taskLed:
            let vmRaw = UserDefaults.standard.string(forKey: TodayDisplayPreferences.taskLedViewMode)
                ?? TodayDisplayPreferences.TaskLedViewMode.timeline.rawValue
            let vm = TodayDisplayPreferences.TaskLedViewMode(rawValue: vmRaw) ?? .timeline
            return vm.title
        default:
            return selectedTab.label
        }
    }
}
