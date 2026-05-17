import Foundation

// MARK: - CueInAppDataKeys

enum CueInAppDataKeys {
    /// When `true`, bundled demo content is removed: empty Tasks store and empty task-led Today blocks.
    static let gimmickDemoRemoved = "cuein.data.gimmickDemoRemoved.v1"
    /// When `true`, the bundled “Test day (empty blocks)” starter scheme is omitted from TimeMap lists and libraries.
    static let hideBundledDummyTestDayTimeMap = "cuein.data.hideBundledDummyTestDayTimeMap.v1"
}

// MARK: - CueInAppDataService

/// Orchestrates local data resets for Settings — Tasks seed, Today schedule persistence, and formula library UserDefaults.
enum CueInAppDataService {

    static var isGimmickDemoRemoved: Bool {
        UserDefaults.standard.bool(forKey: CueInAppDataKeys.gimmickDemoRemoved)
    }

    @MainActor
    static func removeGimmickDemoData() {
        CueInSyncRuntimeBridge.shared.recordWorkspaceDeletion()
        UserDefaults.standard.set(true, forKey: CueInAppDataKeys.gimmickDemoRemoved)
        TasksStore.shared.clearAllTasksData()
        GoalStrategyStore.shared.clearAllGoalsData()
        TodayViewModel.shared.resetSchedulePersistenceAndBlocks(useGimmickTaskLedSample: false)
    }

    @MainActor
    static func restoreGimmickDemoData() {
        UserDefaults.standard.set(false, forKey: CueInAppDataKeys.gimmickDemoRemoved)
        TasksStore.shared.replaceWithGimmickSeed()
        GoalStrategyStore.shared.replaceWithGimmickSeed()
        TodayViewModel.shared.resetSchedulePersistenceAndBlocks(useGimmickTaskLedSample: true)
    }

    @MainActor
    static func clearUserFormulaLibrary() {
        FormulaLibraryService.clearUserSavedTemplates()
        TodayViewModel.shared.reloadAvailableFormulasFromLibrary()
    }

    @MainActor
    static func clearTodayScheduleState() {
        let useSample = !UserDefaults.standard.bool(forKey: CueInAppDataKeys.gimmickDemoRemoved)
        TodayViewModel.shared.resetSchedulePersistenceAndBlocks(useGimmickTaskLedSample: useSample)
    }

    @MainActor
    static func clearTasksTabDataOnly() {
        TasksStore.shared.clearAllTasksData()
        TodayViewModel.shared.syncExecutionTimelineAfterExternalTaskEdit()
    }

    @MainActor
    static func clearGoalsDataOnly() {
        GoalStrategyStore.shared.clearAllGoalsData()
    }

    /// Removes Tasks data, Today schedule snapshots, custom formulas, display prefs, and engine mode — then reapplies bundled demo + defaults like a new install.
    @MainActor
    static func eraseAllLocalData() {
        let defaults = UserDefaults.standard
        TodayDisplayPreferences.removeAllStoredPreferenceKeys(from: defaults)
        defaults.removeObject(forKey: DayEngineMode.storageKey)
        defaults.removeObject(forKey: AppTab.storageKey)
        defaults.removeObject(forKey: CueInAppDataKeys.gimmickDemoRemoved)
        defaults.removeObject(forKey: CueInAppDataKeys.hideBundledDummyTestDayTimeMap)
        FormulaLibraryService.clearUserSavedTemplates()
        TasksStore.shared.replaceWithGimmickSeed()
        GoalStrategyStore.shared.replaceWithGimmickSeed()
        defaults.set(false, forKey: CueInAppDataKeys.gimmickDemoRemoved)
        AntiTodoStore.shared.clearAll()
        MeasureStore.shared.clearAll()
        PomodoroStore.shared.resetForFreshInstall()
        FocusSoundscapeStore.shared.resetForFreshInstall()
        TodayViewModel.shared.performFreshInstallReset()
    }
}
