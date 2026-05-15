import SwiftUI

// MARK: - Goal status

enum GoalStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case active
    case paused
    case completed
    case archived

    var id: String { rawValue }

    var label: String {
        switch self {
        case .active: return "Active"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .archived: return "Archived"
        }
    }

    var icon: String {
        switch self {
        case .active: return "target"
        case .paused: return "pause.circle"
        case .completed: return "checkmark.circle.fill"
        case .archived: return "archivebox.fill"
        }
    }

    var tint: Color {
        switch self {
        case .active: return CueInColors.accentFocus
        case .paused: return CueInColors.textTertiary
        case .completed: return CueInColors.success
        case .archived: return CueInColors.textTertiary
        }
    }
}

enum GoalStageStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case planned
    case active
    case paused
    case completed
    case skipped

    var id: String { rawValue }

    var label: String {
        switch self {
        case .planned: return "Planned"
        case .active: return "Active"
        case .paused: return "Paused"
        case .completed: return "Done"
        case .skipped: return "Skipped"
        }
    }

    var icon: String {
        switch self {
        case .planned: return "circle.dashed"
        case .active: return "circle.dotted"
        case .paused: return "pause.circle"
        case .completed: return "checkmark.circle.fill"
        case .skipped: return "forward.end.circle"
        }
    }

    var tint: Color {
        switch self {
        case .planned: return CueInColors.textTertiary
        case .active: return CueInColors.accentFocus
        case .paused: return CueInColors.textTertiary
        case .completed: return CueInColors.success
        case .skipped: return CueInColors.warning
        }
    }
}

enum GoalSubgoalStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case open
    case active
    case paused
    case completed
    case skipped

    var id: String { rawValue }

    var label: String {
        switch self {
        case .open: return "Open"
        case .active: return "Active"
        case .paused: return "Paused"
        case .completed: return "Done"
        case .skipped: return "Skipped"
        }
    }

    var icon: String {
        switch self {
        case .open: return "circle"
        case .active: return "bolt.circle"
        case .paused: return "pause.circle"
        case .completed: return "checkmark.circle.fill"
        case .skipped: return "forward.end.circle"
        }
    }

    var tint: Color {
        switch self {
        case .open: return CueInColors.textTertiary
        case .active: return CueInColors.accentFocus
        case .paused: return CueInColors.textTertiary
        case .completed: return CueInColors.success
        case .skipped: return CueInColors.warning
        }
    }
}

// MARK: - Work links

struct GoalWorkLink: Identifiable, Codable, Hashable {
    enum TargetKind: String, Codable, CaseIterable, Identifiable, Hashable {
        case field
        case project
        case task

        var id: String { rawValue }

        var label: String {
            switch self {
            case .field: return "Initiative"
            case .project: return "Project"
            case .task: return "Task"
            }
        }

        var icon: String {
            switch self {
            case .field: return "square.grid.2x2.fill"
            case .project: return "folder.fill"
            case .task: return "checklist"
            }
        }
    }

    let id: UUID
    var targetKind: TargetKind
    var targetID: UUID
    var titleSnapshot: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        targetKind: TargetKind,
        targetID: UUID,
        titleSnapshot: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.targetKind = targetKind
        self.targetID = targetID
        self.titleSnapshot = titleSnapshot
        self.createdAt = createdAt
    }
}

// MARK: - Canvas

enum GoalCanvasSection: String, Codable, CaseIterable, Identifiable, Hashable {
    case outcome
    case why
    case currentReality
    case constraints
    case keyLevers
    case risks
    case weeklyCommitment
    case definitionOfDone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .outcome: return "Outcome"
        case .why: return "Why it matters"
        case .currentReality: return "Current reality"
        case .constraints: return "Constraints"
        case .keyLevers: return "Key levers"
        case .risks: return "Risks"
        case .weeklyCommitment: return "Weekly commitment"
        case .definitionOfDone: return "Definition of done"
        }
    }

    var prompt: String {
        switch self {
        case .outcome: return "What will be true when this goal is finished?"
        case .why: return "Why does this matter enough to protect time for it?"
        case .currentReality: return "Where are you starting from right now?"
        case .constraints: return "What limits time, energy, money, access, or focus?"
        case .keyLevers: return "Which actions create the most progress?"
        case .risks: return "What could break the plan, and how will you respond?"
        case .weeklyCommitment: return "What minimum weekly investment keeps this alive?"
        case .definitionOfDone: return "What visible proof means this goal is complete?"
        }
    }

    var icon: String {
        switch self {
        case .outcome: return "flag.checkered"
        case .why: return "heart.text.square.fill"
        case .currentReality: return "location.fill"
        case .constraints: return "exclamationmark.lock.fill"
        case .keyLevers: return "slider.horizontal.3"
        case .risks: return "exclamationmark.triangle.fill"
        case .weeklyCommitment: return "calendar.badge.clock"
        case .definitionOfDone: return "checkmark.seal.fill"
        }
    }
}

struct GoalCanvas: Codable, Hashable {
    var outcome: String
    var why: String
    var currentReality: String
    var constraints: String
    var keyLevers: String
    var risks: String
    var weeklyCommitment: String
    var definitionOfDone: String

    init(
        outcome: String = "",
        why: String = "",
        currentReality: String = "",
        constraints: String = "",
        keyLevers: String = "",
        risks: String = "",
        weeklyCommitment: String = "",
        definitionOfDone: String = ""
    ) {
        self.outcome = outcome
        self.why = why
        self.currentReality = currentReality
        self.constraints = constraints
        self.keyLevers = keyLevers
        self.risks = risks
        self.weeklyCommitment = weeklyCommitment
        self.definitionOfDone = definitionOfDone
    }

    func value(for section: GoalCanvasSection) -> String {
        switch section {
        case .outcome: return outcome
        case .why: return why
        case .currentReality: return currentReality
        case .constraints: return constraints
        case .keyLevers: return keyLevers
        case .risks: return risks
        case .weeklyCommitment: return weeklyCommitment
        case .definitionOfDone: return definitionOfDone
        }
    }

    mutating func setValue(_ value: String, for section: GoalCanvasSection) {
        switch section {
        case .outcome: outcome = value
        case .why: why = value
        case .currentReality: currentReality = value
        case .constraints: constraints = value
        case .keyLevers: keyLevers = value
        case .risks: risks = value
        case .weeklyCommitment: weeklyCommitment = value
        case .definitionOfDone: definitionOfDone = value
        }
    }
}

// MARK: - Goal hierarchy

struct GoalSubgoal: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var notes: String
    var status: GoalSubgoalStatus
    var targetDate: Date?
    var manualProgress: Double
    var linkedWork: [GoalWorkLink]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        status: GoalSubgoalStatus = .open,
        targetDate: Date? = nil,
        manualProgress: Double = 0,
        linkedWork: [GoalWorkLink] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.status = status
        self.targetDate = targetDate
        self.manualProgress = min(max(manualProgress, 0), 1)
        self.linkedWork = linkedWork
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct GoalStage: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var summary: String
    var status: GoalStageStatus
    var targetDate: Date?
    var subgoals: [GoalSubgoal]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        summary: String = "",
        status: GoalStageStatus = .planned,
        targetDate: Date? = nil,
        subgoals: [GoalSubgoal] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.status = status
        self.targetDate = targetDate
        self.subgoals = subgoals
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct GoalReviewEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var moved: String
    var stalled: String
    var changed: String
    var next: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        moved: String = "",
        stalled: String = "",
        changed: String = "",
        next: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.moved = moved
        self.stalled = stalled
        self.changed = changed
        self.next = next
        self.createdAt = createdAt
    }
}

struct Goal: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var why: String
    var successMetric: String
    var notes: String
    var iconName: String
    var colorHex: UInt
    var status: GoalStatus
    var targetDate: Date?
    var stages: [GoalStage]
    var canvas: GoalCanvas
    var reviewEntries: [GoalReviewEntry]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        why: String = "",
        successMetric: String = "",
        notes: String = "",
        iconName: String = "target",
        colorHex: UInt = 0x34C759,
        status: GoalStatus = .active,
        targetDate: Date? = nil,
        stages: [GoalStage] = [],
        canvas: GoalCanvas = GoalCanvas(),
        reviewEntries: [GoalReviewEntry] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.why = why
        self.successMetric = successMetric
        self.notes = notes
        self.iconName = iconName
        self.colorHex = colorHex
        self.status = status
        self.targetDate = targetDate
        self.stages = stages
        self.canvas = canvas
        self.reviewEntries = reviewEntries
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var color: Color { Color(hex: colorHex) }

    var resolvedIconSystemName: String {
        let trimmed = iconName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "target" : trimmed
    }
}

// MARK: - Templates

struct GoalTemplate: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let iconName: String
    let colorHex: UInt
    let why: String
    let canvas: GoalCanvas
    let stages: [GoalStage]

    static let library: [GoalTemplate] = [
        GoalTemplate(
            id: "health",
            title: "Health Reset",
            subtitle: "Body, energy, training",
            iconName: "heart.fill",
            colorHex: 0x5BC6B9,
            why: "Build a body and routine that make everyday life easier.",
            canvas: GoalCanvas(
                outcome: "A sustainable health rhythm I can keep without constant force.",
                keyLevers: "Training, sleep, nutrition, steps, recovery.",
                weeklyCommitment: "Three protected training blocks and one review."
            ),
            stages: [
                GoalStage(title: "Baseline", summary: "Understand the current reality.", status: .active),
                GoalStage(title: "Rhythm", summary: "Build the repeatable weekly structure."),
                GoalStage(title: "Performance", summary: "Increase measurable capacity.")
            ]
        ),
        GoalTemplate(
            id: "product-launch",
            title: "Product Launch",
            subtitle: "Build, test, ship",
            iconName: "paperplane.fill",
            colorHex: 0x34C759,
            why: "Turn the product from idea into something people can use.",
            canvas: GoalCanvas(
                outcome: "A shipped version with a clear core loop and useful first users.",
                keyLevers: "Scope control, weekly shipping, real feedback, quality bar.",
                weeklyCommitment: "One build focus block daily and one weekly product review."
            ),
            stages: [
                GoalStage(title: "Shape", summary: "Define the strongest v1 path.", status: .active),
                GoalStage(title: "Build", summary: "Implement the core experience."),
                GoalStage(title: "Launch", summary: "Ship, observe, and improve.")
            ]
        ),
        GoalTemplate(
            id: "learning",
            title: "Learning Plan",
            subtitle: "Skill, study, practice",
            iconName: "graduationcap.fill",
            colorHex: 0xA99BE0,
            why: "Turn interest into a usable skill through deliberate practice.",
            canvas: GoalCanvas(
                outcome: "I can apply the skill in real projects, not just understand it.",
                keyLevers: "Practice reps, feedback, spaced review, real outputs.",
                weeklyCommitment: "Four focused study blocks and one applied output."
            ),
            stages: [
                GoalStage(title: "Foundation", summary: "Learn the basic map.", status: .active),
                GoalStage(title: "Practice", summary: "Turn knowledge into reps."),
                GoalStage(title: "Application", summary: "Use the skill in real work.")
            ]
        ),
        GoalTemplate(
            id: "career",
            title: "Career Growth",
            subtitle: "Role, leverage, reputation",
            iconName: "chart.line.uptrend.xyaxis",
            colorHex: 0x79B6E8,
            why: "Create better options through stronger output and positioning.",
            canvas: GoalCanvas(
                outcome: "A clearer career direction with visible proof of growth.",
                keyLevers: "Portfolio, relationships, skill depth, opportunity pipeline.",
                weeklyCommitment: "One leverage-building output every week."
            ),
            stages: [
                GoalStage(title: "Direction", summary: "Choose the next career bet.", status: .active),
                GoalStage(title: "Proof", summary: "Build visible evidence."),
                GoalStage(title: "Opportunity", summary: "Create and pursue options.")
            ]
        ),
        GoalTemplate(
            id: "personal-reset",
            title: "Personal Reset",
            subtitle: "Order, energy, clarity",
            iconName: "sparkles",
            colorHex: 0xE2B253,
            why: "Reduce life drag and make the default week easier to live.",
            canvas: GoalCanvas(
                outcome: "A cleaner personal system with less friction and more calm.",
                keyLevers: "Environment, routines, commitments, review.",
                weeklyCommitment: "One reset block and one planning block per week."
            ),
            stages: [
                GoalStage(title: "Clear", summary: "Remove obvious friction.", status: .active),
                GoalStage(title: "Organize", summary: "Set up simple systems."),
                GoalStage(title: "Maintain", summary: "Keep it alive without overthinking.")
            ]
        )
    ]
}
