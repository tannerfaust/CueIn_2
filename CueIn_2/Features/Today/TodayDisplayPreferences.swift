import Foundation
import SwiftUI

enum TodayDisplayPreferences {
    static let showScheduleStartTime  = "today.schedule.showStartTime"
    static let showScheduleDuration   = "today.schedule.showDuration"
    static let showScheduleTimeRange  = "today.schedule.showTimeRange"
    /// When `true` (default), Timeline fill blocks on the schedule claim tasks from the execution pool.
    static let pullsTasksFromExecutionPool = "today.schedule.pullsTasksFromExecutionPool"
    /// Task-led Today presentation: timeline calendar or execution-pool to-do list.
    static let taskLedViewMode       = "today.taskLed.viewMode"
    /// When `true`, To-do view shows summary info (placement set by ``todoSummaryPlacement``).
    static let todoViewShowInfoBlock = "today.taskLed.todo.showInfoBlock"
    /// Large pill under the title vs compact pill in the top chrome (left of the menu).
    static let todoSummaryPlacement = "today.taskLed.todo.summary.placement"
    /// Which single metric the top-bar summary pill shows when placement is chrome.
    static let todoChromeSummaryMetric = "today.taskLed.todo.summary.chromeMetric"
    /// Visual treatment for each task in To-do view: classic list or soft framed rows.
    static let todoTaskBlockStyle = "today.taskLed.todo.taskBlockStyle"
    /// Vertical padding inside each task row.
    static let todoRowDensity = "today.taskLed.todo.rowDensity"
    static let todoSummaryShowPlannedTime = "today.taskLed.todo.summary.showPlannedTime"
    static let todoSummaryShowMetricPills = "today.taskLed.todo.summary.showMetricPills"
    static let todoShowCompletedSection = "today.taskLed.todo.showCompletedSection"
    static let todoShowSectionCountBadge = "today.taskLed.todo.showSectionCountBadge"
    static let todoShowEmptyStateMessage = "today.taskLed.todo.showEmptyStateMessage"
    static let todoRowShowCheckbox = "today.taskLed.todo.row.showCheckbox"
    static let todoRowShowPriorityIcon = "today.taskLed.todo.row.showPriorityIcon"
    static let todoRowShowOverdueIcon = "today.taskLed.todo.row.showOverdueIcon"
    static let todoRowShowProjectOrFieldPill = "today.taskLed.todo.row.showProjectOrFieldPill"
    /// When the project/field pill is on: `true` = colored icon only (field tint); `false` = icon + name (project/field tint as today).
    static let todoRowProjectOrFieldPillIconOnly = "today.taskLed.todo.row.projectOrFieldPillIconOnly"
    static let todoRowShowPlannedMinutes = "today.taskLed.todo.row.showPlannedMinutes"
    static let todoRowShowDueDate = "today.taskLed.todo.row.showDueDate"
    static let todoRowShowTags = "today.taskLed.todo.row.showTags"
    static let todoRowShowNotesPreview = "today.taskLed.todo.row.showNotesPreview"
    static let todoRowShowLeadingFieldAccent = "today.taskLed.todo.row.showLeadingFieldAccent"
    static let todoRowShowInProgressDetails = "today.taskLed.todo.row.showInProgressDetails"
    static let todoRowShowWorkTypeChip = "today.taskLed.todo.row.showWorkTypeChip"
    static let todoRowShowSubtasks = "today.taskLed.todo.row.showSubtasks"

    /// Keys for To-do appearance in ``TodayTodoSettingsSection`` (used when discarding the Today settings sheet).
    static let todoAppearanceStorageKeys: [String] = [
        todoViewShowInfoBlock,
        todoSummaryPlacement,
        todoChromeSummaryMetric,
        todoTaskBlockStyle,
        todoRowDensity,
        todoSummaryShowPlannedTime,
        todoSummaryShowMetricPills,
        todoShowCompletedSection,
        todoShowSectionCountBadge,
        todoShowEmptyStateMessage,
        todoRowShowCheckbox,
        todoRowShowPriorityIcon,
        todoRowShowOverdueIcon,
        todoRowShowProjectOrFieldPill,
        todoRowShowPlannedMinutes,
        todoRowShowDueDate,
        todoRowShowTags,
        todoRowShowNotesPreview,
        todoRowShowLeadingFieldAccent,
        todoRowShowInProgressDetails,
        todoRowShowWorkTypeChip,
        todoRowShowSubtasks
    ]

    /// Property-list snapshot of To-do–scoped defaults (for settings discard).
    static func snapshotTodoAppearancePlist(defaults: UserDefaults = .standard) -> Data? {
        var dict: [String: Any] = [:]
        for key in todoAppearanceStorageKeys {
            if let obj = defaults.object(forKey: key) {
                dict[key] = obj
            } else {
                dict[key] = NSNull()
            }
        }
        return try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
    }

    /// Re-applies a snapshot from ``snapshotTodoAppearancePlist( )``; missing keys are removed.
    static func restoreTodoAppearance(from data: Data?, defaults: UserDefaults = .standard) {
        guard let data,
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = obj as? [String: Any] else { return }
        for key in todoAppearanceStorageKeys {
            guard let stored = dict[key] else { continue }
            if stored is NSNull {
                defaults.removeObject(forKey: key)
            } else {
                defaults.set(stored, forKey: key)
            }
        }
    }

    static let scheduleDesign         = "today.schedule.design"
    static let runningLineStyle       = "today.schedule.runningLineStyle"
    /// Optional dot grid behind schedule (formula) scroll content; visual only.
    static let canvasDotsBackground   = "today.canvasDotsBackground"
    /// Accent for the *current* (running) block and the running line.
    static let activeBlockEmphasis   = "today.schedule.activeBlockEmphasis"
    /// Padding / typography scale for the live running line.
    static let runningLineSize       = "today.schedule.runningLineSize"
    /// Thickness of progress bars and orbit ring stroke.
    static let runningLineBarWeight  = "today.schedule.runningLineBarWeight"
    /// Faux card / material behind the running line (styles that support it).
    static let runningLineFrostedCard = "today.schedule.runningLineFrostedCard"
    /// Show the current block name in the running line when the style has room for it.
    static let runningLineShowBlockTitle = "today.schedule.runningLineShowBlockTitle"
    /// Show the day’s percent complete where the style shows a number.
    static let runningLineShowDayPercent = "today.schedule.runningLineShowDayPercent"
    /// What happens when a stopped schedule resumes.
    static let schedulePauseBehavior = "today.schedule.pauseBehavior"
    /// Optional play/pause control in the Today chrome while a schedule is running or paused.
    static let scheduleShowsPagePlaybackControl = "today.schedule.showsPagePlaybackControl"
    /// Per-block live timer style shown in schedule rows.
    static let scheduleBlockTimerStyle = "today.schedule.blockTimer.style"
    /// Whether schedule row timers show seconds.
    static let scheduleBlockTimerShowsSeconds = "today.schedule.blockTimer.showsSeconds"
    /// Legacy engine keys kept for migration compatibility; runtime behavior now
    /// uses fixed defaults in code.
    static let scheduleGlueToFinishTime = "today.schedule.engine.glueToFinishTime"
    static let scheduleRedistributeEarlyFinish = "today.schedule.engine.redistributeEarlyFinish"
    static let scheduleLiveOverrunRecalibration = "today.schedule.engine.liveOverrunRecalibration"
    static let scheduleProtectFixedTimeBlocks = "today.schedule.engine.protectFixedTimeBlocks"
    static let scheduleAvoidTinyBlocks = "today.schedule.engine.avoidTinyBlocks"
    static let schedulePriorityWeightedRebalance = "today.schedule.engine.priorityWeightedRebalance"
    static let scheduleMinimumFlexibleBlockMinutes = "today.schedule.engine.minimumFlexibleBlockMinutes"
    static let enableCategoryTracking = "today.schedule.enableCategoryTracking"

    // MARK: Timeblock focus mode (full-screen)

    static let timeblockFocusShowBlockIcon = "today.timeblockFocus.showBlockIcon"
    static let timeblockFocusShowNowLabel = "today.timeblockFocus.showNowLabel"
    static let timeblockFocusShowTimeRange = "today.timeblockFocus.showTimeRange"
    static let timeblockFocusShowProgressBar = "today.timeblockFocus.showProgressBar"
    static let timeblockFocusShowRemainingLine = "today.timeblockFocus.showRemainingLine"
    static let timeblockFocusShowTaskCount = "today.timeblockFocus.showTaskCount"
    static let timeblockFocusTimerShowsSeconds = "today.timeblockFocus.timerShowsSeconds"

    static let timeblockFocusStorageKeys: [String] = [
        timeblockFocusShowBlockIcon,
        timeblockFocusShowNowLabel,
        timeblockFocusShowTimeRange,
        timeblockFocusShowProgressBar,
        timeblockFocusShowRemainingLine,
        timeblockFocusShowTaskCount,
        timeblockFocusTimerShowsSeconds,
    ]

    /// Keys written through Today UI / `@AppStorage` — used for “erase everything”.
    static let allStoredPreferenceKeys: [String] = [
        showScheduleStartTime,
        showScheduleDuration,
        showScheduleTimeRange,
        pullsTasksFromExecutionPool,
        taskLedViewMode,
        todoViewShowInfoBlock,
        todoSummaryPlacement,
        todoChromeSummaryMetric,
        todoTaskBlockStyle,
        todoRowDensity,
        todoSummaryShowPlannedTime,
        todoSummaryShowMetricPills,
        todoShowCompletedSection,
        todoShowSectionCountBadge,
        todoShowEmptyStateMessage,
        todoRowShowCheckbox,
        todoRowShowPriorityIcon,
        todoRowShowOverdueIcon,
        todoRowShowProjectOrFieldPill,
        todoRowProjectOrFieldPillIconOnly,
        todoRowShowPlannedMinutes,
        todoRowShowDueDate,
        todoRowShowTags,
        todoRowShowNotesPreview,
        todoRowShowLeadingFieldAccent,
        todoRowShowInProgressDetails,
        todoRowShowWorkTypeChip,
        todoRowShowSubtasks,
        scheduleDesign,
        runningLineStyle,
        canvasDotsBackground,
        activeBlockEmphasis,
        runningLineSize,
        runningLineBarWeight,
        runningLineFrostedCard,
        runningLineShowBlockTitle,
        runningLineShowDayPercent,
        schedulePauseBehavior,
        scheduleShowsPagePlaybackControl,
        scheduleBlockTimerStyle,
        scheduleBlockTimerShowsSeconds,
        timelineHourHeight,
        timelineLayoutMode,
        scheduleGlueToFinishTime,
        scheduleRedistributeEarlyFinish,
        scheduleLiveOverrunRecalibration,
        scheduleProtectFixedTimeBlocks,
        scheduleAvoidTinyBlocks,
        schedulePriorityWeightedRebalance,
        scheduleMinimumFlexibleBlockMinutes,
        enableCategoryTracking,
        timeblockFocusShowBlockIcon,
        timeblockFocusShowNowLabel,
        timeblockFocusShowTimeRange,
        timeblockFocusShowProgressBar,
        timeblockFocusShowRemainingLine,
        timeblockFocusShowTaskCount,
        timeblockFocusTimerShowsSeconds,
    ]

    static func removeAllStoredPreferenceKeys(from defaults: UserDefaults = .standard) {
        for key in allStoredPreferenceKeys {
            defaults.removeObject(forKey: key)
        }
    }

    /// Reads ``pullsTasksFromExecutionPool``; missing key defaults to `true` (matches `@AppStorage` default).
    static func pullsTasksFromExecutionPoolPreference(_ defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: pullsTasksFromExecutionPool) == nil { return true }
        return defaults.bool(forKey: pullsTasksFromExecutionPool)
    }

    static func glueToFinishTimePreference(_ defaults: UserDefaults = .standard) -> Bool {
        _ = defaults
        return true
    }

    static func redistributeEarlyFinishPreference(_ defaults: UserDefaults = .standard) -> Bool {
        _ = defaults
        return true
    }

    static func liveOverrunRecalibrationPreference(_ defaults: UserDefaults = .standard) -> Bool {
        _ = defaults
        return true
    }

    static func protectFixedTimeBlocksPreference(_ defaults: UserDefaults = .standard) -> Bool {
        _ = defaults
        return true
    }

    static func avoidTinyBlocksPreference(_ defaults: UserDefaults = .standard) -> Bool {
        _ = defaults
        return false
    }

    static func priorityWeightedRebalancePreference(_ defaults: UserDefaults = .standard) -> Bool {
        _ = defaults
        return true
    }

    static func minimumFlexibleBlockMinutesPreference(_ defaults: UserDefaults = .standard) -> Int {
        _ = defaults
        return 25
    }

    private static func boolPreference(_ key: String, defaultValue: Bool, defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    // MARK: Timeline

    /// Persisted hour-height (points per hour) for the execution timeline.
    static let timelineHourHeight        = "today.timeline.hourHeight"
    static let timelineHourHeightDefault = 80.0

    /// "vertical" = endless vertical scroll (default); "paged" = swipe left/right per day.
    static let timelineLayoutMode        = "today.timeline.layoutMode"

    enum TimelineLayoutMode: String {
        case vertical = "vertical"
        case paged    = "paged"
    }

    enum TaskLedViewMode: String, CaseIterable, Identifiable {
        case timeline
        case todo

        var id: String { rawValue }

        var title: String {
            switch self {
            case .timeline: return "Timeline"
            case .todo: return "To-do"
            }
        }

        var icon: String {
            switch self {
            case .timeline: return "calendar.day.timeline.left"
            case .todo: return "checklist"
            }
        }
    }

    // MARK: Today to-do summary placement

    enum TodoSummaryPlacement: String, CaseIterable, Identifiable {
        case inList = "inList"
        case inChrome = "inChrome"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .inList: return "In list"
            case .inChrome: return "Top bar"
            }
        }
    }

    enum TodoChromeSummaryMetric: String, CaseIterable, Identifiable {
        case plannedTime = "plannedTime"
        case openCount = "openCount"
        case completedCount = "completedCount"
        case totalCount = "totalCount"
        case openAndPlanned = "openAndPlanned"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .plannedTime: return "Planned time"
            case .openCount: return "Open tasks"
            case .completedCount: return "Done"
            case .totalCount: return "Total tasks"
            case .openAndPlanned: return "Open + time"
            }
        }
    }

    enum TodoTaskBlockStyle: String, CaseIterable, Identifiable {
        /// Continuous list with inset dividers between tasks.
        case listClassic = "listClassic"
        /// Soft rounded blocks on a whisper-lifted surface - no borders (iOS-style grouping).
        case frames = "frames"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .listClassic: return "Classic"
            case .frames: return "Frames"
            }
        }

        var subtitle: String {
            switch self {
            case .listClassic:
                return "Hairline dividers between tasks."
            case .frames:
                return "Each task on a slightly lighter rounded surface, no outlines."
            }
        }

        var icon: String {
            switch self {
            case .listClassic: return "list.bullet"
            case .frames: return "rectangle.fill"
            }
        }
    }

    enum TodoRowDensity: String, CaseIterable, Identifiable {
        case compact
        case regular
        case relaxed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .compact: return "Compact"
            case .regular: return "Regular"
            case .relaxed: return "Relaxed"
            }
        }

        /// Main row vertical padding (one side); total row height scales with this.
        var verticalPadding: CGFloat {
            switch self {
            case .compact: return 5
            case .regular: return 9
            case .relaxed: return 13
            }
        }

        var blockSpacing: CGFloat {
            switch self {
            case .compact: return 6
            case .regular: return 10
            case .relaxed: return 14
            }
        }
    }

    static func migratedTodoTaskBlockStyle(from raw: String) -> TodoTaskBlockStyle {
        if raw == TodoTaskBlockStyle.frames.rawValue { return .frames }
        if raw == TodoTaskBlockStyle.listClassic.rawValue { return .listClassic }
        // Legacy: separate cards, minimal, inset — fold into Classic.
        return .listClassic
    }

    static func migratedTodoRowDensity(from raw: String) -> TodoRowDensity {
        TodoRowDensity(rawValue: raw) ?? .regular
    }

    static func migratedTodoSummaryPlacement(from raw: String) -> TodoSummaryPlacement {
        TodoSummaryPlacement(rawValue: raw) ?? .inList
    }

    static func migratedTodoChromeSummaryMetric(from raw: String) -> TodoChromeSummaryMetric {
        TodoChromeSummaryMetric(rawValue: raw) ?? .openAndPlanned
    }

    /// Short label for total planned minutes on open Today tasks (To-do summary).
    static func formatTodoPlannedMinutesLine(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
        }
        return "\(minutes)m"
    }

    // MARK: Schedule

    enum ScheduleDesign: String, CaseIterable, Identifiable {
        case glass = "glass"
        case reminders = "reminders"
        case agenda = "agenda"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .glass: return "Liquid glass"
            case .reminders: return "Reminders"
            case .agenda: return "Day agenda"
            }
        }

        var subtitle: String {
            switch self {
            case .glass:
                return "Frosted glass surface with soft corners"
            case .reminders:
                return "Edgeless rows, hairlines, leading disk (like Reminders)"
            case .agenda:
                return "Time column, rule, and details — no card chrome"
            }
        }

        var icon: String {
            switch self {
            case .glass: return "sparkles"
            case .reminders: return "list.bullet"
            case .agenda: return "calendar.day.timeline.left"
            }
        }
    }

    /// Maps old storage keys to the current design set so users don’t land on removed styles.
    static func migratedScheduleDesign(from storageRaw: String) -> ScheduleDesign {
        if storageRaw == "rail" || storageRaw == "strips" { return .reminders }
        if storageRaw == "frames" { return .glass }
        return ScheduleDesign(rawValue: storageRaw) ?? .glass
    }

    /// How the live schedule “running” header looks while a day is running.
    enum RunningLineStyle: String, CaseIterable, Identifiable {
        case minimal = "minimal"
        case bar = "bar"
        case liquid = "liquid"
        case orbit = "orbit"
        case ticker = "ticker"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .minimal: return "Minimal (percent only)"
            case .bar: return "Bar (labels & time)"
            case .liquid: return "Liquid"
            case .orbit: return "Orbit"
            case .ticker: return "Ticker"
            }
        }

        /// Short label for horizontal style chips in settings.
        var chipTitle: String {
            switch self {
            case .minimal: return "Minimal"
            case .bar: return "Bar"
            case .liquid: return "Liquid"
            case .orbit: return "Orbit"
            case .ticker: return "Ticker"
            }
        }

        var subtitle: String {
            switch self {
            case .minimal: return "Day progress bar and percentage only"
            case .bar: return "Schedule label, block title, time left, and bar"
            case .liquid: return "Large capsule, soft glass, chip timer"
            case .orbit: return "Ring for day, title + time outside"
            case .ticker: return "One dense band: icon, focus, time"
            }
        }

        var icon: String {
            switch self {
            case .minimal: return "percent"
            case .bar: return "chart.bar"
            case .liquid: return "cloud.fill"
            case .orbit: return "circle.dotted"
            case .ticker: return "text.append"
            }
        }
    }

    /// Resolves stored running-line style; unknown values fall back to the current default.
    static func migratedRunningLineStyle(from storageRaw: String) -> RunningLineStyle {
        RunningLineStyle(rawValue: storageRaw) ?? .minimal
    }

    enum SchedulePauseBehavior: String, CaseIterable, Identifiable {
        case preserveLength = "preserveLength"
        case compressRemaining = "compressRemaining"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .preserveLength: return "End later"
            case .compressRemaining: return "Compress remaining"
            }
        }

        var subtitle: String {
            switch self {
            case .preserveLength:
                return "Paused time is added to the schedule, preserving remaining block lengths."
            case .compressRemaining:
                return "Remaining blocks are replanned into the original end time using schedule intelligence."
            }
        }

        var icon: String {
            switch self {
            case .preserveLength: return "clock.badge.plus"
            case .compressRemaining: return "arrow.down.forward.and.arrow.up.backward"
            }
        }
    }

    static func migratedSchedulePauseBehavior(from storageRaw: String) -> SchedulePauseBehavior {
        SchedulePauseBehavior(rawValue: storageRaw) ?? .preserveLength
    }

    static func schedulePauseBehaviorPreference(_ defaults: UserDefaults = .standard) -> SchedulePauseBehavior {
        migratedSchedulePauseBehavior(from: defaults.string(forKey: schedulePauseBehavior) ?? SchedulePauseBehavior.preserveLength.rawValue)
    }

    // MARK: Running line layout

    enum RunningLineSize: String, CaseIterable, Identifiable {
        case compact
        case standard
        case prominent

        var id: String { rawValue }

        var title: String {
            switch self {
            case .compact: return "Compact"
            case .standard: return "Default"
            case .prominent: return "Roomy"
            }
        }
    }

    static func migratedRunningLineSize(from storageRaw: String) -> RunningLineSize {
        RunningLineSize(rawValue: storageRaw) ?? .standard
    }

    enum RunningLineBarWeight: String, CaseIterable, Identifiable {
        case thin
        case standard
        case heavy

        var id: String { rawValue }

        var title: String {
            switch self {
            case .thin: return "Thin"
            case .standard: return "Medium"
            case .heavy: return "Bold"
            }
        }
    }

    static func migratedRunningLineBarWeight(from storageRaw: String) -> RunningLineBarWeight {
        RunningLineBarWeight(rawValue: storageRaw) ?? .standard
    }

    // MARK: Active (running) block + running line color

    enum ActiveBlockEmphasis: String, CaseIterable, Identifiable {
        case brand
        case monochrome
        case warm
        case cool
        case lilac

        var id: String { rawValue }

        var title: String {
            switch self {
            case .brand: return "Brand (green)"
            case .monochrome: return "White & grey"
            case .warm: return "Amber"
            case .cool: return "Teal"
            case .lilac: return "Lilac"
            }
        }

        var subtitle: String {
            switch self {
            case .brand: return "CueIn green focus — default"
            case .monochrome: return "No hue; soft white / silver highlights"
            case .warm: return "Amber / gold energy"
            case .cool: return "Calm sea-green"
            case .lilac: return "Soft purple accent"
            }
        }

        var icon: String {
            switch self {
            case .brand: return "leaf.fill"
            case .monochrome: return "circle.hexagongrid.fill"
            case .warm: return "sun.max.fill"
            case .cool: return "drop.fill"
            case .lilac: return "sparkle"
            }
        }
    }

    static func migratedActiveBlockEmphasis(from storageRaw: String) -> ActiveBlockEmphasis {
        ActiveBlockEmphasis(rawValue: storageRaw) ?? .brand
    }

    // MARK: Named scale steps

    struct TimelineScale: Identifiable, Hashable {
        let id: String
        let label: String
        let hourHeight: Double
    }

    static let timelineScales: [TimelineScale] = [
        TimelineScale(id: "compact",  label: "Compact",  hourHeight: 56),
        TimelineScale(id: "default",  label: "Default",  hourHeight: 80),
        TimelineScale(id: "spacious", label: "Spacious", hourHeight: 110),
        TimelineScale(id: "large",    label: "Large",    hourHeight: 148),
    ]
}

extension TodayDisplayPreferences.ScheduleDesign {
    /// Rounded swiped row vs edgeless: should match the visible block outline so swipes and clips feel correct.
    var blockInteractionClipRadius: CGFloat {
        switch self {
        case .glass: return 22
        case .reminders, .agenda: return 0
        }
    }

    var usesListHairlinesBetweenBlocks: Bool {
        self == .reminders || self == .agenda
    }
}

extension TodayDisplayPreferences {
    enum ScheduleBlockTimerStyle: String, CaseIterable, Identifiable {
        case ring
        case pulse
        case bars
        case minimal

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ring: return "Ring"
            case .pulse: return "Pulse"
            case .bars: return "Bars"
            case .minimal: return "Minimal"
            }
        }

        var subtitle: String {
            switch self {
            case .ring: return "Circular progress around the time"
            case .pulse: return "Soft breathing disk with countdown"
            case .bars: return "Segment bars that fill over time"
            case .minimal: return "Time text only, no animation"
            }
        }

        var icon: String {
            switch self {
            case .ring: return "timelapse"
            case .pulse: return "dot.radiowaves.left.and.right"
            case .bars: return "chart.bar.xaxis"
            case .minimal: return "timer"
            }
        }
    }

    static func migratedScheduleBlockTimerStyle(from raw: String) -> ScheduleBlockTimerStyle {
        ScheduleBlockTimerStyle(rawValue: raw) ?? .ring
    }
}

// MARK: - Active block / running line palette

extension TodayDisplayPreferences.ActiveBlockEmphasis {
    /// Main accent (rings, live timer stroke, glass tint, running-line primary).
    var primary: Color {
        switch self {
        case .brand: return CueInColors.accentFocus
        case .monochrome: return Color(white: 0.9)
        case .warm: return CueInColors.accentFixed
        case .cool: return CueInColors.accentRoutine
        case .lilac: return CueInColors.accentMini
        }
    }

    /// Second stop for gradients (bar / orbit) so fills stay legible.
    var gradientPartner: Color {
        switch self {
        case .brand: return CueInColors.accentRoutine
        case .monochrome: return Color(white: 0.45)
        case .warm: return Color(red: 0.95, green: 0.62, blue: 0.28)
        case .cool: return Color(red: 0.35, green: 0.75, blue: 0.68)
        case .lilac: return Color(red: 0.72, green: 0.65, blue: 0.95)
        }
    }

    /// One word under the color ring in settings.
    var shortName: String {
        switch self {
        case .brand: return "Brand"
        case .monochrome: return "Grey"
        case .warm: return "Amber"
        case .cool: return "Teal"
        case .lilac: return "Lilac"
        }
    }

    var swatchColor: Color { primary }
}

// MARK: - Running line metrics

extension TodayDisplayPreferences.RunningLineSize {
    /// Scales vertical padding on the running-line chrome.
    var paddingScale: CGFloat {
        switch self {
        case .compact: return 0.8
        case .standard: return 1.0
        case .prominent: return 1.2
        }
    }

    var liquidBlockTitleSize: CGFloat {
        switch self {
        case .compact: return 17
        case .standard: return 20
        case .prominent: return 22
        }
    }
}

extension TodayDisplayPreferences.RunningLineBarWeight {
    /// Main horizontal track / capsule height (minimal, bar, liquid).
    func trackHeight(for lineStyle: TodayDisplayPreferences.RunningLineStyle) -> CGFloat {
        switch lineStyle {
        case .minimal, .bar:
            switch self {
            case .thin: return 5
            case .standard: return 7
            case .heavy: return 10
            }
        case .liquid:
            switch self {
            case .thin: return 10
            case .standard: return 14
            case .heavy: return 18
            }
        case .orbit, .ticker:
            return 0
        }
    }

    /// Orbit ring outer diameter.
    func orbitDiameter(lineSize: TodayDisplayPreferences.RunningLineSize) -> CGFloat {
        let base: CGFloat
        switch self {
        case .thin: base = 48
        case .standard: base = 56
        case .heavy: base = 64
        }
        switch lineSize {
        case .compact: return base - 4
        case .standard: return base
        case .prominent: return base + 6
        }
    }

    /// Orbit ring stroke width.
    func orbitStrokeWidth() -> CGFloat {
        switch self {
        case .thin: return 4
        case .standard: return 5
        case .heavy: return 6.5
        }
    }

    /// Ticker leading icon box.
    func tickerIconSide(lineSize: TodayDisplayPreferences.RunningLineSize) -> CGFloat {
        switch lineSize {
        case .compact: return 40
        case .standard: return 44
        case .prominent: return 48
        }
    }
}
