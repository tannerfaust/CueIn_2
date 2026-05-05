import Foundation
import Observation
import SwiftUI

// MARK: - DevNotebookContext

/// Live shell location for dev notebook captures (tab + optional screen title).
@MainActor
@Observable
final class DevNotebookContext {
    static let shared = DevNotebookContext()

    var selectedTab: AppTab = .today
    var screenLabel: String?

    private init() {}

    /// Builds module + context strings from the current tab, optional screen label, and persisted Today prefs.
    func makeSnapshot() -> (moduleLabel: String, contextLine: String) {
        let moduleLabel = selectedTab.label

        var parts: [String] = [moduleLabel]

        if selectedTab == .today {
            let modeRaw = UserDefaults.standard.string(forKey: DayEngineMode.storageKey) ?? DayEngineMode.taskLed.rawValue
            let mode = DayEngineMode(rawValue: modeRaw) ?? .taskLed
            parts.append(mode.label)
            if mode == .taskLed {
                let vmRaw = UserDefaults.standard.string(forKey: TodayDisplayPreferences.taskLedViewMode)
                    ?? TodayDisplayPreferences.TaskLedViewMode.timeline.rawValue
                let vm = TodayDisplayPreferences.TaskLedViewMode(rawValue: vmRaw) ?? .timeline
                parts.append(vm.title)
            }
        }

        if let s = screenLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            parts.append(s)
        }

        return (moduleLabel, parts.joined(separator: " · "))
    }
}
