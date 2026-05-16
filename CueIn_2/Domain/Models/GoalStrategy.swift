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

struct Goal: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var description: String
    var status: GoalStatus
    var targetDate: Date?
    var stages: [GoalStage]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        description: String = "",
        status: GoalStatus = .active,
        targetDate: Date? = nil,
        stages: [GoalStage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
        self.targetDate = targetDate
        self.stages = stages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Templates

struct GoalTemplate: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let stages: [GoalStage]

    static let library: [GoalTemplate] = [
        GoalTemplate(
            id: "product-launch",
            title: "Product Launch",
            description: "Turn the product from idea into something people can use.",
            stages: [
                GoalStage(title: "Shape", summary: "Define the strongest v1 path.", status: .active),
                GoalStage(title: "Build", summary: "Implement the core experience."),
                GoalStage(title: "Launch", summary: "Ship, observe, and improve.")
            ]
        ),
        GoalTemplate(
            id: "learning",
            title: "Learning Plan",
            description: "Turn interest into a usable skill through deliberate practice.",
            stages: [
                GoalStage(title: "Foundation", summary: "Learn the basic map.", status: .active),
                GoalStage(title: "Practice", summary: "Turn knowledge into reps."),
                GoalStage(title: "Application", summary: "Use the skill in real work.")
            ]
        )
    ]
}
