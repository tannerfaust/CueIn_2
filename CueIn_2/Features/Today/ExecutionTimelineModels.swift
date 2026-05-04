import Foundation

// MARK: - ExecutionLane

enum ExecutionLane: Int, CaseIterable, Identifiable, Codable {
    case focus
    case admin
    case life

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .admin: return "Admin"
        case .life: return "Life"
        }
    }

    static func suggested(for blockType: BlockType) -> ExecutionLane {
        switch blockType {
        case .focus:
            return .focus
        case .fixed, .mini:
            return .admin
        case .routine:
            return .life
        }
    }
}

// MARK: - ExecutionTaskCard

struct ExecutionTaskCard: Identifiable, Codable {
    let id: UUID
    let sourceBlockID: UUID?
    let sourceTaskID: UUID?
    var title: String
    var blockTitle: String
    var blockTypeLabel: String
    /// Accent / lane hint for tinting (legacy pool rows may still use `.fixed` alongside `pinsToClock`).
    var blockType: BlockType
    var startDate: Date
    var durationMinutes: Int
    var lane: ExecutionLane
    var isCompleted: Bool
    var isRepeating: Bool
    var isPrimary: Bool
    var field: String? = nil
    var project: String? = nil
    var folder: String? = nil
    /// When set, this row was queued from the Tasks planner; toggling completion
    /// on the Today execution timeline updates that `TaskItem` in `TasksStore`.
    var plannerTaskItemID: UUID? = nil
    /// When set, this card was *injected* by the live Schedule (e.g. a Routine
    /// block shown on the Timeline so both surfaces stay aligned). It is owned
    /// by the schedule lifecycle — created on Start, removed on Stop / Reset.
    var scheduleInjectedBlockID: UUID? = nil
    /// Immovable clock anchor on the Timeline (meetings, pinned schedule windows).
    var pinsToClock: Bool
    /// Optional 0xRRGGBB — cosmetic match for schedule block accent override.
    var timelineAccentHex: UInt32? = nil

    var endDate: Date {
        Calendar.current.date(byAdding: .minute, value: durationMinutes, to: startDate) ?? startDate
    }

    /// `true` when this card belongs to the live schedule projection (not a
    /// free-standing pool task). Used by `TodayViewModel.syncExecutionPool…`
    /// to avoid garbage-collecting it, and by the Timeline UI to render the
    /// schedule-origin badge.
    var isScheduleInjected: Bool { scheduleInjectedBlockID != nil }

    /// Immovable anchor for drag/reflow — pinned clock card or schedule injection.
    var isTimelineAnchor: Bool { pinsToClock || isScheduleInjected }

    enum CodingKeys: String, CodingKey {
        case id, sourceBlockID, sourceTaskID, title, blockTitle, blockTypeLabel
        case blockType, startDate, durationMinutes, lane, isCompleted, isRepeating, isPrimary
        case field, project, folder, plannerTaskItemID, scheduleInjectedBlockID, pinsToClock
        case timelineAccentHex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sourceBlockID = try c.decodeIfPresent(UUID.self, forKey: .sourceBlockID)
        sourceTaskID = try c.decodeIfPresent(UUID.self, forKey: .sourceTaskID)
        title = try c.decode(String.self, forKey: .title)
        blockTitle = try c.decode(String.self, forKey: .blockTitle)
        blockTypeLabel = try c.decode(String.self, forKey: .blockTypeLabel)
        let decodedBlockType = try c.decode(BlockType.self, forKey: .blockType)
        blockType = decodedBlockType
        startDate = try c.decode(Date.self, forKey: .startDate)
        durationMinutes = try c.decode(Int.self, forKey: .durationMinutes)
        lane = try c.decode(ExecutionLane.self, forKey: .lane)
        isCompleted = try c.decode(Bool.self, forKey: .isCompleted)
        isRepeating = try c.decode(Bool.self, forKey: .isRepeating)
        isPrimary = try c.decode(Bool.self, forKey: .isPrimary)
        field = try c.decodeIfPresent(String.self, forKey: .field)
        project = try c.decodeIfPresent(String.self, forKey: .project)
        folder = try c.decodeIfPresent(String.self, forKey: .folder)
        plannerTaskItemID = try c.decodeIfPresent(UUID.self, forKey: .plannerTaskItemID)
        scheduleInjectedBlockID = try c.decodeIfPresent(UUID.self, forKey: .scheduleInjectedBlockID)
        pinsToClock = try c.decodeIfPresent(Bool.self, forKey: .pinsToClock) ?? (decodedBlockType == .fixed)
        timelineAccentHex = try c.decodeIfPresent(UInt32.self, forKey: .timelineAccentHex)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(sourceBlockID, forKey: .sourceBlockID)
        try c.encodeIfPresent(sourceTaskID, forKey: .sourceTaskID)
        try c.encode(title, forKey: .title)
        try c.encode(blockTitle, forKey: .blockTitle)
        try c.encode(blockTypeLabel, forKey: .blockTypeLabel)
        try c.encode(blockType, forKey: .blockType)
        try c.encode(startDate, forKey: .startDate)
        try c.encode(durationMinutes, forKey: .durationMinutes)
        try c.encode(lane, forKey: .lane)
        try c.encode(isCompleted, forKey: .isCompleted)
        try c.encode(isRepeating, forKey: .isRepeating)
        try c.encode(isPrimary, forKey: .isPrimary)
        try c.encodeIfPresent(field, forKey: .field)
        try c.encodeIfPresent(project, forKey: .project)
        try c.encodeIfPresent(folder, forKey: .folder)
        try c.encodeIfPresent(plannerTaskItemID, forKey: .plannerTaskItemID)
        try c.encodeIfPresent(scheduleInjectedBlockID, forKey: .scheduleInjectedBlockID)
        try c.encode(pinsToClock, forKey: .pinsToClock)
        try c.encodeIfPresent(timelineAccentHex, forKey: .timelineAccentHex)
    }

    init(
        id: UUID,
        sourceBlockID: UUID?,
        sourceTaskID: UUID?,
        title: String,
        blockTitle: String,
        blockTypeLabel: String,
        blockType: BlockType,
        startDate: Date,
        durationMinutes: Int,
        lane: ExecutionLane,
        isCompleted: Bool,
        isRepeating: Bool,
        isPrimary: Bool,
        field: String? = nil,
        project: String? = nil,
        folder: String? = nil,
        plannerTaskItemID: UUID? = nil,
        scheduleInjectedBlockID: UUID? = nil,
        pinsToClock: Bool = false,
        timelineAccentHex: UInt32? = nil
    ) {
        self.id = id
        self.sourceBlockID = sourceBlockID
        self.sourceTaskID = sourceTaskID
        self.title = title
        self.blockTitle = blockTitle
        self.blockTypeLabel = blockTypeLabel
        self.blockType = blockType
        self.startDate = startDate
        self.durationMinutes = durationMinutes
        self.lane = lane
        self.isCompleted = isCompleted
        self.isRepeating = isRepeating
        self.isPrimary = isPrimary
        self.field = field
        self.project = project
        self.folder = folder
        self.plannerTaskItemID = plannerTaskItemID
        self.scheduleInjectedBlockID = scheduleInjectedBlockID
        self.pinsToClock = pinsToClock
        self.timelineAccentHex = timelineAccentHex
    }
}

// MARK: - ExecutionDayPlan

struct ExecutionDayPlan: Identifiable, Codable {
    let id: Date
    var date: Date
    var tasks: [ExecutionTaskCard]

    var openTaskCount: Int {
        tasks.filter { !$0.isCompleted }.count
    }

    var priorityTaskCount: Int {
        tasks.filter { $0.isPrimary && !$0.isCompleted }.count
    }

    /// Cheap identity for SwiftUI `onChange`: start time, duration, and completion.
    var taskLayoutFingerprint: String {
        if tasks.isEmpty { return "0" }
        var s = ""
        s.reserveCapacity(tasks.count * 32)
        for t in tasks {
            s += t.id.uuidString
            s += String(Int(t.startDate.timeIntervalSinceReferenceDate))
            s += ".\(t.durationMinutes)."
            s += t.isCompleted ? "1" : "0"
            s += ","
        }
        return s
    }
}
