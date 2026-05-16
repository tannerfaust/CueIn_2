import Foundation

// MARK: - StatsDisplayPreferences
/// Keys for the Stats tab only (`@AppStorage` / UserDefaults).

enum StatsDisplayPreferences {
    static let showActivityRings = "stats.showActivityRings"
    static let showTodayProgressCard = "stats.showTodayProgressCard"
    static let showWeeklySnapshot = "stats.showWeeklySnapshot"
    static let showTimeAllocation = "stats.showTimeAllocation"
    static let showTrends = "stats.showTrends"
    static let showActivitySparkline = "stats.showActivitySparkline"

    /// Minutes from local midnight for a typical wake time (default 7:00).
    static let dayWakeMinutes = "stats.dayWakeMinutes"
    /// Minutes from local midnight for target sleep (default 23:00).
    static let daySleepMinutes = "stats.daySleepMinutes"

    static let dayWakeMinutesDefault = 7 * 60
    static let daySleepMinutesDefault = 23 * 60

    static func clampWakeMinutes(_ value: Int) -> Int {
        min(max(value, 0), 24 * 60 - 1)
    }

    /// Ensures sleep is strictly after wake on the same calendar day.
    static func clampSleepMinutes(wakeMinutes: Int, sleepMinutes: Int) -> Int {
        let wake = clampWakeMinutes(wakeMinutes)
        let raw = min(max(sleepMinutes, wake + 30), 24 * 60 - 1)
        return raw
    }
}
