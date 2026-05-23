import Foundation

// MARK: - ScheduleTaskDraft

struct ScheduleTaskDraft: Identifiable, Equatable {
    var id: UUID
    var title: String
    var isPrimary: Bool
    /// When set, this row mirrors a ``TaskItem`` in ``TasksStore`` (created via the full task sheet).
    var plannerTaskItemID: UUID?

    init(id: UUID = UUID(), title: String, isPrimary: Bool = false, plannerTaskItemID: UUID? = nil) {
        self.id = id
        self.title = title
        self.isPrimary = isPrimary
        self.plannerTaskItemID = plannerTaskItemID
    }
}

// MARK: - ScheduleBlockDraft

struct ScheduleBlockDraft: Identifiable {
    var id: UUID
    var title: String
    /// Timeline / lane accent only — not a rigid “block kind”.
    var timelineAccent: BlockType
    /// Optional SF Symbol name for the row glyph; empty uses ``BlockType/icon`` for `timelineAccent`.
    var timelineGlyph: String?
    /// Optional 0xRRGGBB cosmetic colour; `nil` uses `BlockType` accent.
    var timelineAccentHex: UInt32?
    var durationMinutes: Int
    var flowMode: BlockFlowMode
    /// When false, this block is **time only** (maps to ``ScheduleBlockTaskSource/noTasks``).
    var assignsTasks: Bool
    /// When `assignsTasks` is true, optional Timeline pool autofill (maps with manual tasks to ``ScheduleBlockTaskSource/executionFill``).
    /// Manual linked tasks are kept first; pool cards append after when autofill runs.
    var poolFillEnabled: Bool
    var fillField: String
    var fillProject: String
    var deepWorkOnly: Bool
    /// How autofill ranks pool tasks (see ``AutofillTaskPickOrder``).
    var autofillPickOrder: AutofillTaskPickOrder
    /// Manual rows when `assignsTasks` (titles sync from ``TasksStore`` when ``ScheduleTaskDraft/plannerTaskItemID`` is set). When autofill is on, pool-filled rows are appended at runtime after these.
    var tasks: [ScheduleTaskDraft]
    var isRepeatable: Bool
    /// Pin start/end to explicit clock positions (other blocks flow around).
    var pinsToClock: Bool
    /// When `pinsToClock`, minutes from local midnight for start (length comes from duration).
    var fixedClockMinutesFromDayStart: Int?
    /// Calendar day used with ``fixedClockMinutesFromDayStart`` while editing a concrete schedule block.
    /// Formula templates keep using the run day when materialized.
    var fixedClockDate: Date?
    /// 1…100, optional — higher = more protected when the day compresses (nil = default 50).
    var schedulingPriority: Int?
    /// Compact strip presentation (legacy; hidden from editor — decoded for older schedules).
    var compactPresentation: Bool
    /// Prefer keeping planned length when the day compresses (flexible blocks shrink first).
    var locksPlannedDuration: Bool
    /// Editor-only precision for active block retiming; persisted model remains minute-based.
    var liveDurationOverrideSeconds: Int?
    
    /// Optional tracking category for this block (e.g. Work, Others).
    var category: String = "Others"
    /// Flag to check if category was manually overwritten by user.
    var isCategoryManuallySet: Bool = false

    /// Maps editor flags to the persisted schedule source.
    var resolvedTaskSource: ScheduleBlockTaskSource {
        guard assignsTasks else { return .noTasks }
        if poolFillEnabled { return .executionFill }
        return .templateTasks
    }

    init(
        id: UUID = UUID(),
        title: String,
        timelineAccent: BlockType,
        timelineGlyph: String? = nil,
        durationMinutes: Int,
        flowMode: BlockFlowMode,
        assignsTasks: Bool,
        poolFillEnabled: Bool = false,
        fillField: String = "",
        fillProject: String = "",
        deepWorkOnly: Bool = false,
        autofillPickOrder: AutofillTaskPickOrder = .priority,
        tasks: [ScheduleTaskDraft] = [],
        isRepeatable: Bool = false,
        pinsToClock: Bool = false,
        fixedClockMinutesFromDayStart: Int? = nil,
        fixedClockDate: Date? = nil,
        schedulingPriority: Int? = nil,
        compactPresentation: Bool = false,
        locksPlannedDuration: Bool = false,
        timelineAccentHex: UInt32? = nil,
        liveDurationOverrideSeconds: Int? = nil,
        category: String = "Others",
        isCategoryManuallySet: Bool = false
    ) {
        self.id = id
        self.title = title
        self.timelineAccent = timelineAccent
        self.timelineGlyph = timelineGlyph
        self.timelineAccentHex = timelineAccentHex
        self.durationMinutes = durationMinutes
        self.flowMode = flowMode
        self.assignsTasks = assignsTasks
        self.poolFillEnabled = poolFillEnabled
        self.fillField = fillField
        self.fillProject = fillProject
        self.deepWorkOnly = deepWorkOnly
        self.autofillPickOrder = autofillPickOrder
        self.tasks = tasks
        self.isRepeatable = isRepeatable
        self.pinsToClock = pinsToClock
        self.fixedClockMinutesFromDayStart = fixedClockMinutesFromDayStart
        self.fixedClockDate = fixedClockDate.map { Calendar.current.startOfDay(for: $0) }
        self.schedulingPriority = schedulingPriority
        self.compactPresentation = compactPresentation
        self.locksPlannedDuration = locksPlannedDuration
        self.liveDurationOverrideSeconds = liveDurationOverrideSeconds
        self.category = category
        self.isCategoryManuallySet = isCategoryManuallySet
    }

    init(from block: DayBlock) {
        id = block.id
        title = block.title
        timelineAccent = block.type
        timelineGlyph = block.timelineGlyph
        timelineAccentHex = block.timelineAccentHex
        durationMinutes = max(5, block.durationMinutes)
        flowMode = block.flowMode
        switch block.taskSource {
        case .noTasks:
            assignsTasks = false
            poolFillEnabled = false
        case .executionFill:
            assignsTasks = true
            poolFillEnabled = true
        case .templateTasks:
            assignsTasks = true
            poolFillEnabled = false
        }
        fillField = block.fillRule?.field ?? ""
        fillProject = block.fillRule?.project ?? ""
        deepWorkOnly = block.fillRule?.deepWorkOnly ?? false
        autofillPickOrder = block.fillRule?.pickOrder ?? .priority
        switch block.taskSource {
        case .noTasks:
            tasks = []
        case .executionFill:
            tasks = block.tasks
                .filter { $0.sourceExecutionTaskID == nil }
                .map {
                    ScheduleTaskDraft(
                        id: $0.id,
                        title: $0.title,
                        isPrimary: $0.isPrimary,
                        plannerTaskItemID: $0.plannerTaskItemID
                    )
                }
        case .templateTasks:
            tasks = block.tasks.map {
                ScheduleTaskDraft(
                    id: $0.id,
                    title: $0.title,
                    isPrimary: $0.isPrimary,
                    plannerTaskItemID: $0.plannerTaskItemID
                )
            }
        }
        isRepeatable = block.isRepeatable
        pinsToClock = block.pinsToClock
        schedulingPriority = block.schedulingPriority
        compactPresentation = block.compactPresentation
        locksPlannedDuration = block.locksPlannedDuration
        liveDurationOverrideSeconds = nil
        category = block.category
        isCategoryManuallySet = block.isCategoryManuallySet
        if block.pinsToClock {
            let dayStart = Calendar.current.startOfDay(for: block.startTime)
            let mins = Int(block.startTime.timeIntervalSince(dayStart) / 60)
            fixedClockMinutesFromDayStart = max(0, min(24 * 60 - 1, mins))
            fixedClockDate = dayStart
        } else {
            fixedClockMinutesFromDayStart = nil
            fixedClockDate = nil
        }
    }

    init(from template: DayFormulaBlockTemplate) {
        id = UUID()
        title = template.title
        timelineAccent = template.type
        timelineGlyph = template.timelineGlyph
        timelineAccentHex = template.timelineAccentHex
        durationMinutes = max(5, template.durationMinutes)
        flowMode = template.flowMode
        switch template.taskSource {
        case .noTasks:
            assignsTasks = false
            poolFillEnabled = false
        case .executionFill:
            assignsTasks = true
            poolFillEnabled = true
        case .templateTasks:
            assignsTasks = true
            poolFillEnabled = false
        }
        fillField = template.fillRule?.field ?? ""
        fillProject = template.fillRule?.project ?? ""
        deepWorkOnly = template.fillRule?.deepWorkOnly ?? false
        autofillPickOrder = template.fillRule?.pickOrder ?? .priority
        switch template.taskSource {
        case .executionFill, .noTasks:
            tasks = []
        case .templateTasks:
            tasks = template.tasks.map {
                ScheduleTaskDraft(
                    id: $0.id,
                    title: $0.title,
                    isPrimary: $0.isPrimary,
                    plannerTaskItemID: $0.plannerTaskItemID
                )
            }
        }
        isRepeatable = template.isRepeatable
        pinsToClock = template.pinsToClock
        fixedClockMinutesFromDayStart = template.fixedClockMinutesFromDayStart
        fixedClockDate = template.pinsToClock ? Calendar.current.startOfDay(for: Date()) : nil
        schedulingPriority = template.schedulingPriority
        compactPresentation = template.compactPresentation
        locksPlannedDuration = template.locksPlannedDuration
        liveDurationOverrideSeconds = nil
        category = template.category
        isCategoryManuallySet = template.isCategoryManuallySet
    }

    /// Replace fields from a library preset while keeping this block’s identity (same row in the builder).
    mutating func applyPreset(from template: DayFormulaBlockTemplate) {
        let keepID = id
        self = ScheduleBlockDraft(from: template)
        id = keepID
    }

    static func routineTemplate() -> ScheduleBlockDraft {
        ScheduleBlockDraft(
            title: "Morning Routine",
            timelineAccent: .routine,
            timelineGlyph: nil,
            durationMinutes: 45,
            flowMode: .blocking,
            assignsTasks: true,
            poolFillEnabled: false,
            tasks: [
                ScheduleTaskDraft(title: "Hydrate & stretch", isPrimary: true),
                ScheduleTaskDraft(title: "Journal priorities")
            ],
            isRepeatable: false
        )
    }

    static func executionFillTemplate() -> ScheduleBlockDraft {
        ScheduleBlockDraft(
            title: "Deep Work Frame",
            timelineAccent: .focus,
            timelineGlyph: nil,
            durationMinutes: 90,
            flowMode: .blocking,
            assignsTasks: true,
            poolFillEnabled: true,
            deepWorkOnly: false,
            tasks: [],
            isRepeatable: false
        )
    }

    static func noTasksTemplate() -> ScheduleBlockDraft {
        ScheduleBlockDraft(
            title: "Time block",
            timelineAccent: .mini,
            timelineGlyph: nil,
            durationMinutes: 30,
            flowMode: .flowing,
            assignsTasks: false,
            poolFillEnabled: false,
            tasks: [],
            isRepeatable: false
        )
    }

    var fillRule: ScheduleFillRule {
        ScheduleFillRule(
            blockType: nil,
            field: fillField.isEmpty ? nil : fillField,
            project: fillProject.isEmpty ? nil : fillProject,
            folder: nil,
            deepWorkOnly: deepWorkOnly,
            pickOrder: autofillPickOrder
        )
    }

    func mergedDayTasks(previousTasks: [DayTask]) -> [DayTask] {
        let previousByID = Dictionary(uniqueKeysWithValues: previousTasks.map { ($0.id, $0) })
        return tasks.compactMap { draft -> DayTask? in
            let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let prev = previousByID[draft.id] {
                var next = prev
                next.title = trimmed
                next.isPrimary = draft.isPrimary
                next.isRepeating = false
                if let pid = draft.plannerTaskItemID {
                    next.plannerTaskItemID = pid
                }
                return next
            }
            return DayTask(
                id: draft.id,
                title: trimmed,
                isCompleted: false,
                isPrimary: draft.isPrimary,
                isRepeating: false,
                sourceExecutionBlockID: id,
                sourceExecutionTaskID: nil,
                plannerTaskItemID: draft.plannerTaskItemID,
                field: nil,
                project: nil,
                folder: nil
            )
        }
    }

    func toFormulaBlockTemplate() -> DayFormulaBlockTemplate {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let ts = resolvedTaskSource
        let tasksOut: [DayTask]
        switch ts {
        case .templateTasks:
            tasksOut = materializedTemplateTasks
        case .executionFill, .noTasks:
            tasksOut = []
        }
        return DayFormulaBlockTemplate(
            id: id,
            title: trimmedTitle,
            type: timelineAccent,
            durationMinutes: max(durationMinutes, 5),
            flowMode: flowMode,
            taskSource: ts,
            fillMatchesType: nil,
            fillRule: ts == .executionFill ? fillRule : nil,
            tasks: tasksOut,
            isRepeatable: false,
            pinsToClock: pinsToClock,
            fixedClockMinutesFromDayStart: pinsToClock ? fixedClockMinutesFromDayStart : nil,
            schedulingPriority: schedulingPriority,
            compactPresentation: compactPresentation,
            locksPlannedDuration: locksPlannedDuration,
            timelineGlyph: timelineGlyph,
            timelineAccentHex: timelineAccentHex,
            category: category,
            isCategoryManuallySet: isCategoryManuallySet
        )
    }

    /// Glyph for builder rows — optional symbol or accent default.
    var resolvedTimelineGlyph: String {
        let trimmed = timelineGlyph?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return timelineAccent.icon
    }

    var materializedTemplateTasks: [DayTask] {
        mergedDayTasks(previousTasks: [])
    }

    /// Single-line summary for collapsed schedule-builder rows.
    var subtitleLine: String {
        var parts: [String] = []
        if compactPresentation {
            parts.append("Compact")
        }
        if pinsToClock, let mins = fixedClockMinutesFromDayStart {
            parts.append("Pinned \(ScheduleBlockFormat.shortClockLabel(minutesFromMidnight: mins))")
        } else if pinsToClock {
            parts.append("Pinned time")
        }
        if let p = schedulingPriority, !locksPlannedDuration {
            parts.append(schedulingPriorityLabel(p))
        }
        if locksPlannedDuration {
            parts.append("Fix duration")
        }
        parts.append(flowMode == .flowing ? "Flowing" : "Blocking")
        let tail: String
        if !assignsTasks {
            tail = "No tasks"
        } else if poolFillEnabled {
            let manualCount = tasks.count
            let manualBit = manualCount == 0 ? "" : "\(manualCount) tasks · "
            tail = "Autofill · \(manualBit)\(fillRule.displayLabel)"
        } else {
            let count = tasks.count
            if count == 0 {
                tail = "Tasks · none yet"
            } else {
                let suffix = count == 1 ? "task" : "tasks"
                tail = "Tasks · \(count) \(suffix)"
            }
        }
        if parts.isEmpty { return tail }
        return parts.joined(separator: " · ") + " · " + tail
    }
}

private func schedulingPriorityLabel(_ priority: Int) -> String {
    if priority >= 65 { return "High priority" }
    return "Balanced"
}

// MARK: - ScheduleMakerTaskScopes

struct ScheduleMakerTaskScopes: Equatable {
    var fields: [String]
    var projects: [String]
    var folders: [String]

    static let empty = ScheduleMakerTaskScopes(fields: [], projects: [], folders: [])

    init(fields: [String], projects: [String], folders: [String]) {
        self.fields = fields.cleanedSorted
        self.projects = projects.cleanedSorted
        self.folders = folders.cleanedSorted
    }

    init(tasks: [ExecutionTaskCard]) {
        self.init(
            fields: tasks.compactMap(\.field),
            projects: tasks.compactMap(\.project),
            folders: tasks.compactMap(\.folder)
        )
    }
}

extension Array where Element == String {
    fileprivate var cleanedSorted: [String] {
        Array(
            Set(
                map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

// MARK: - ScheduleBlockFormat

enum ScheduleBlockFormat {
    static func durationLabel(minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60

        if hours > 0, remainder > 0 {
            return "\(hours)h \(remainder)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }

    static func shortClockLabel(minutesFromMidnight: Int) -> String {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        guard let at = cal.date(byAdding: .minute, value: minutesFromMidnight, to: base) else {
            return "\(minutesFromMidnight)m"
        }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: at)
    }
}
