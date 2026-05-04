import Foundation

// MARK: - DayFormulaTemplate
/// Lightweight formula model for CueIn_2's Today mode.

struct DayFormulaTemplate: Identifiable, Codable {
    let id: UUID
    var name: String
    var symbol: String
    var summary: String
    var targetDurationMinutes: Int
    var rules: [String]
    var blocks: [DayFormulaBlockTemplate]

    var blockCount: Int { blocks.count }

    var totalTaskCount: Int {
        blocks.reduce(0) { $0 + $1.tasks.count }
    }

    var executionFilledBlockCount: Int {
        blocks.filter { $0.taskSource == .executionFill }.count
    }

    var totalNominalMinutes: Int {
        blocks.reduce(0) { $0 + max($1.durationMinutes, 1) }
    }

    var targetDurationLabel: String {
        Self.durationLabel(minutes: max(targetDurationMinutes, totalNominalMinutes))
    }

    var previewTitles: String {
        blocks.prefix(3).map(\.title).joined(separator: " · ")
    }

    func materializeDay(startingAt startDate: Date, includeExecutionFillTasks: Bool = false) -> [DayBlock] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: startDate)
        var cursor = startDate

        return blocks.map { template in
            let duration = max(template.durationMinutes, 1)

            let startTime: Date
            let endTime: Date

            if template.pinsToClock, let mins = template.fixedClockMinutesFromDayStart {
                let pinnedStart = cal.date(byAdding: .minute, value: mins, to: dayStart) ?? dayStart
                startTime = pinnedStart
                endTime = cal.date(byAdding: .minute, value: duration, to: pinnedStart) ?? pinnedStart
                cursor = max(cursor, endTime)
            } else {
                startTime = cursor
                endTime = cal.date(byAdding: .minute, value: duration, to: cursor) ?? cursor
                cursor = endTime
            }

            let materializedTasks: [DayTask]
            switch template.taskSource {
            case .noTasks:
                materializedTasks = []
            case .executionFill:
                materializedTasks = includeExecutionFillTasks ? template.tasks : []
            case .templateTasks:
                materializedTasks = template.tasks
            }

            return DayBlock(
                id: template.id,
                title: template.title,
                type: template.type,
                state: .upcoming,
                startTime: startTime,
                endTime: endTime,
                flowMode: template.flowMode,
                taskSource: template.taskSource,
                fillMatchesType: template.fillMatchesType,
                fillRule: template.fillRule,
                tasks: materializedTasks,
                isRepeatable: template.isRepeatable,
                pinsToClock: template.pinsToClock,
                schedulingPriority: template.schedulingPriority,
                compactPresentation: template.compactPresentation,
                locksPlannedDuration: template.locksPlannedDuration,
                timelineGlyph: template.timelineGlyph,
                timelineAccentHex: template.timelineAccentHex
            )
        }
    }

    private static func durationLabel(minutes: Int) -> String {
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
}

struct DayFormulaBlockTemplate: Identifiable, Codable {
    let id: UUID
    var title: String
    var type: BlockType
    var durationMinutes: Int
    var flowMode: BlockFlowMode
    var taskSource: ScheduleBlockTaskSource
    var fillMatchesType: BlockType?
    var fillRule: ScheduleFillRule?
    var tasks: [DayTask]
    var isRepeatable: Bool
    /// When true, `fixedClockMinutesFromDayStart` pins the block on the day clock.
    var pinsToClock: Bool
    /// Optional explicit clock start (minutes from local midnight); requires `pinsToClock`.
    var fixedClockMinutesFromDayStart: Int?
    var schedulingPriority: Int?
    var compactPresentation: Bool
    var locksPlannedDuration: Bool
    /// Optional SF Symbol name persisted with the block template.
    var timelineGlyph: String?
    /// Optional 0xRRGGBB cosmetic colour for timeline / icon.
    var timelineAccentHex: UInt32?

    init(
        id: UUID = UUID(),
        title: String,
        type: BlockType,
        durationMinutes: Int,
        flowMode: BlockFlowMode = .blocking,
        taskSource: ScheduleBlockTaskSource = .templateTasks,
        fillMatchesType: BlockType? = nil,
        fillRule: ScheduleFillRule? = nil,
        tasks: [DayTask] = [],
        isRepeatable: Bool = false,
        pinsToClock: Bool = false,
        fixedClockMinutesFromDayStart: Int? = nil,
        schedulingPriority: Int? = nil,
        compactPresentation: Bool = false,
        locksPlannedDuration: Bool = false,
        timelineGlyph: String? = nil,
        timelineAccentHex: UInt32? = nil
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.durationMinutes = durationMinutes
        self.flowMode = flowMode
        self.taskSource = taskSource
        self.fillMatchesType = fillMatchesType
        self.fillRule = fillRule
        self.tasks = tasks
        self.isRepeatable = isRepeatable
        self.pinsToClock = pinsToClock
        self.fixedClockMinutesFromDayStart = fixedClockMinutesFromDayStart
        self.schedulingPriority = schedulingPriority
        self.compactPresentation = compactPresentation
        self.locksPlannedDuration = locksPlannedDuration
        self.timelineGlyph = timelineGlyph
        self.timelineAccentHex = timelineAccentHex
    }

    enum CodingKeys: String, CodingKey {
        case id, title, type, durationMinutes, flowMode, taskSource
        case fillMatchesType, fillRule, tasks, isRepeatable
        case pinsToClock, fixedClockMinutesFromDayStart, schedulingPriority, compactPresentation, locksPlannedDuration, timelineGlyph
        case timelineAccentHex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        let decodedType = try c.decode(BlockType.self, forKey: .type)
        type = decodedType
        durationMinutes = try c.decode(Int.self, forKey: .durationMinutes)
        flowMode = try c.decode(BlockFlowMode.self, forKey: .flowMode)
        taskSource = try c.decode(ScheduleBlockTaskSource.self, forKey: .taskSource)
        fillMatchesType = try c.decodeIfPresent(BlockType.self, forKey: .fillMatchesType)
        fillRule = try c.decodeIfPresent(ScheduleFillRule.self, forKey: .fillRule)
        tasks = try c.decode([DayTask].self, forKey: .tasks)
        isRepeatable = try c.decode(Bool.self, forKey: .isRepeatable)
        fixedClockMinutesFromDayStart = try c.decodeIfPresent(Int.self, forKey: .fixedClockMinutesFromDayStart)
        schedulingPriority = try c.decodeIfPresent(Int.self, forKey: .schedulingPriority)

        pinsToClock = try c.decodeIfPresent(Bool.self, forKey: .pinsToClock)
            ?? (decodedType == .fixed || fixedClockMinutesFromDayStart != nil)
        compactPresentation = try c.decodeIfPresent(Bool.self, forKey: .compactPresentation) ?? (decodedType == .mini)
        locksPlannedDuration = try c.decodeIfPresent(Bool.self, forKey: .locksPlannedDuration) ?? false
        timelineGlyph = try c.decodeIfPresent(String.self, forKey: .timelineGlyph)
        timelineAccentHex = try c.decodeIfPresent(UInt32.self, forKey: .timelineAccentHex)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(type, forKey: .type)
        try c.encode(durationMinutes, forKey: .durationMinutes)
        try c.encode(flowMode, forKey: .flowMode)
        try c.encode(taskSource, forKey: .taskSource)
        try c.encodeIfPresent(fillMatchesType, forKey: .fillMatchesType)
        try c.encodeIfPresent(fillRule, forKey: .fillRule)
        try c.encode(tasks, forKey: .tasks)
        try c.encode(isRepeatable, forKey: .isRepeatable)
        try c.encode(pinsToClock, forKey: .pinsToClock)
        try c.encodeIfPresent(fixedClockMinutesFromDayStart, forKey: .fixedClockMinutesFromDayStart)
        try c.encodeIfPresent(schedulingPriority, forKey: .schedulingPriority)
        try c.encode(compactPresentation, forKey: .compactPresentation)
        try c.encode(locksPlannedDuration, forKey: .locksPlannedDuration)
        try c.encodeIfPresent(timelineGlyph, forKey: .timelineGlyph)
        try c.encodeIfPresent(timelineAccentHex, forKey: .timelineAccentHex)
    }
}

extension DayFormulaBlockTemplate {
    /// Glyph when browsing presets — optional stored symbol or ``BlockType/icon``.
    var resolvedTimelineGlyph: String {
        let trimmed = timelineGlyph?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return type.icon
    }

    /// Snapshot for the user preset library — new block id so it does not collide with live builder rows.
    func copyWithNewID() -> DayFormulaBlockTemplate {
        withID(UUID())
    }

    /// Same template fields with a specific id (e.g. keep library id when updating a saved preset by name).
    func withID(_ id: UUID) -> DayFormulaBlockTemplate {
        DayFormulaBlockTemplate(
            id: id,
            title: title,
            type: type,
            durationMinutes: durationMinutes,
            flowMode: flowMode,
            taskSource: taskSource,
            fillMatchesType: fillMatchesType,
            fillRule: fillRule,
            tasks: tasks,
            isRepeatable: isRepeatable,
            pinsToClock: pinsToClock,
            fixedClockMinutesFromDayStart: fixedClockMinutesFromDayStart,
            schedulingPriority: schedulingPriority,
            compactPresentation: compactPresentation,
            locksPlannedDuration: locksPlannedDuration,
            timelineGlyph: timelineGlyph,
            timelineAccentHex: timelineAccentHex
        )
    }
}
