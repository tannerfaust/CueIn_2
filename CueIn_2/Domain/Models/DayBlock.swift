import Foundation

// MARK: - DayBlock
/// A time-bounded block that structures a CueIn day.
/// Scheduling uses explicit flags (`pinsToClock`, `schedulingPriority`, …).
/// `type` is **timeline accent / lane hint** (and legacy pool-card filter fallback), not a rigid “kind”.

struct DayBlock: Identifiable, Codable {
    let id: UUID
    var title: String
    /// Timeline tint / lane hint — **not** the schedule role (see `pinsToClock`, `compactPresentation`).
    var type: BlockType
    /// Optional SF Symbol name for the block glyph; when nil, ``type/icon`` is used.
    var timelineGlyph: String?
    /// Optional 0xRRGGBB cosmetic colour; `nil` uses `BlockType` accent.
    var timelineAccentHex: UInt32?
    var state: BlockState
    var startTime: Date
    var endTime: Date
    /// In a timeless run, controls whether the next block waits on you or advances on its own.
    var flowMode: BlockFlowMode
    var taskSource: ScheduleBlockTaskSource
    var fillMatchesType: BlockType?
    var fillRule: ScheduleFillRule?
    var tasks: [DayTask]
    var isRepeatable: Bool
    /// When true, start time is anchored on the clock; flexible blocks reflow around this window.
    var pinsToClock: Bool
    /// Higher values resist proportional shrink when the day is compressed (nil = default 50).
    var schedulingPriority: Int?
    /// Optional compact strip presentation (“mini” UI), independent of accent.
    var compactPresentation: Bool
    /// When true, proportional day planning keeps this block at its planned length until impossible (flexible blocks shrink first).
    var locksPlannedDuration: Bool
    /// When set, this block was injected into the live Schedule to represent
    /// a time-anchored task from the Timeline pool (an "anchor"). Anchors are
    /// removed from the Schedule on Stop / Reset; the card stays in the
    /// Timeline pool untouched.
    var anchorExecutionCardID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        type: BlockType,
        state: BlockState = .upcoming,
        startTime: Date,
        endTime: Date,
        flowMode: BlockFlowMode = .blocking,
        taskSource: ScheduleBlockTaskSource = .templateTasks,
        fillMatchesType: BlockType? = nil,
        fillRule: ScheduleFillRule? = nil,
        tasks: [DayTask] = [],
        isRepeatable: Bool = false,
        pinsToClock: Bool = false,
        schedulingPriority: Int? = nil,
        compactPresentation: Bool = false,
        locksPlannedDuration: Bool = false,
        timelineGlyph: String? = nil,
        timelineAccentHex: UInt32? = nil,
        anchorExecutionCardID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.state = state
        self.startTime = startTime
        self.endTime = endTime
        self.flowMode = flowMode
        self.taskSource = taskSource
        self.fillMatchesType = fillMatchesType
        self.fillRule = fillRule
        self.tasks = tasks
        self.isRepeatable = isRepeatable
        self.pinsToClock = pinsToClock
        self.schedulingPriority = schedulingPriority
        self.compactPresentation = compactPresentation
        self.locksPlannedDuration = locksPlannedDuration
        self.timelineGlyph = timelineGlyph
        self.timelineAccentHex = timelineAccentHex
        self.anchorExecutionCardID = anchorExecutionCardID
    }

    /// Glyph shown on cards and lists — custom symbol or fallback to ``BlockType/icon``.
    var resolvedTimelineGlyph: String {
        let trimmed = timelineGlyph?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return type.icon
    }

    /// `true` when the block was pinned into the schedule from a timeline anchor.
    var isAnchorBlock: Bool { anchorExecutionCardID != nil }

    /// Effective priority for proportional reshuffles (1…100); default mid tier.
    var effectiveSchedulingPriority: Int {
        let p = schedulingPriority ?? 50
        return min(100, max(1, p))
    }

    // MARK: Computed

    var timeRangeLabel: String {
        "\(CueInTimeFormat.hourMinute(startTime)) – \(CueInTimeFormat.hourMinute(endTime))"
    }

    var durationMinutes: Int {
        Int(endTime.timeIntervalSince(startTime) / 60)
    }

    var completedTaskCount: Int {
        tasks.filter(\.isCompleted).count
    }

    var taskProgress: Double {
        guard !tasks.isEmpty else { return 0 }
        return Double(completedTaskCount) / Double(tasks.count)
    }

    // MARK: Codable (migration from older saves where `.fixed` / `.mini` encoded the role)

    enum CodingKeys: String, CodingKey {
        case id, title, type, state, startTime, endTime, flowMode
        case taskSource, fillMatchesType, fillRule, tasks, isRepeatable, anchorExecutionCardID
        case pinsToClock, schedulingPriority, compactPresentation, locksPlannedDuration, timelineGlyph
        case timelineAccentHex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        let decodedType = try c.decode(BlockType.self, forKey: .type)
        type = decodedType
        state = try c.decode(BlockState.self, forKey: .state)
        startTime = try c.decode(Date.self, forKey: .startTime)
        endTime = try c.decode(Date.self, forKey: .endTime)
        flowMode = try c.decode(BlockFlowMode.self, forKey: .flowMode)
        taskSource = try c.decode(ScheduleBlockTaskSource.self, forKey: .taskSource)
        fillMatchesType = try c.decodeIfPresent(BlockType.self, forKey: .fillMatchesType)
        fillRule = try c.decodeIfPresent(ScheduleFillRule.self, forKey: .fillRule)
        tasks = try c.decode([DayTask].self, forKey: .tasks)
        isRepeatable = try c.decode(Bool.self, forKey: .isRepeatable)
        anchorExecutionCardID = try c.decodeIfPresent(UUID.self, forKey: .anchorExecutionCardID)

        pinsToClock = try c.decodeIfPresent(Bool.self, forKey: .pinsToClock) ?? (decodedType == .fixed)
        schedulingPriority = try c.decodeIfPresent(Int.self, forKey: .schedulingPriority)
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
        try c.encode(state, forKey: .state)
        try c.encode(startTime, forKey: .startTime)
        try c.encode(endTime, forKey: .endTime)
        try c.encode(flowMode, forKey: .flowMode)
        try c.encode(taskSource, forKey: .taskSource)
        try c.encodeIfPresent(fillMatchesType, forKey: .fillMatchesType)
        try c.encodeIfPresent(fillRule, forKey: .fillRule)
        try c.encode(tasks, forKey: .tasks)
        try c.encode(isRepeatable, forKey: .isRepeatable)
        try c.encodeIfPresent(anchorExecutionCardID, forKey: .anchorExecutionCardID)
        try c.encode(pinsToClock, forKey: .pinsToClock)
        try c.encodeIfPresent(schedulingPriority, forKey: .schedulingPriority)
        try c.encode(compactPresentation, forKey: .compactPresentation)
        try c.encode(locksPlannedDuration, forKey: .locksPlannedDuration)
        try c.encodeIfPresent(timelineGlyph, forKey: .timelineGlyph)
        try c.encodeIfPresent(timelineAccentHex, forKey: .timelineAccentHex)
    }
}
