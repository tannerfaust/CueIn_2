import Foundation
import SwiftUI

enum TasksRoute: Hashable {
    case collection(TaskCollectionKind)
    case priority
    case initiatives
    case projects(ProjectSourceFilter?)
    case field(UUID)
    case project(UUID)
}

/// Filters the project library (Plan vs Notion/Linear sidebar entry).
enum ProjectSourceFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case cueIn
    case notion
    case linear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .cueIn: return "CueIn"
        case .notion: return "Notion"
        case .linear: return "Linear"
        }
    }
}

enum TasksWorklistKind: Hashable, Identifiable {
    case tasks
    case collection(TaskCollectionKind)
    case archived
    case completed
    case saved
    case habits
    case rituals
    case notionTasks
    case notionProjects
    case linearTasks
    case linearProjects
    case field(UUID)
    case project(UUID)

    var id: String {
        switch self {
        case .tasks: return "tasks"
        case .collection(let kind): return "collection:\(kind.rawValue)"
        case .archived: return "archived"
        case .completed: return "completed"
        case .saved: return "saved"
        case .habits: return "habits"
        case .rituals: return "rituals"
        case .notionTasks: return "notion:tasks"
        case .notionProjects: return "notion:projects"
        case .linearTasks: return "linear:tasks"
        case .linearProjects: return "linear:projects"
        case .field(let id): return "field:\(id.uuidString)"
        case .project(let id): return "project:\(id.uuidString)"
        }
    }
}

enum TaskCollectionKind: String, CaseIterable, Identifiable, Hashable {
    case today
    case inbox
    case upcoming
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "To-do"
        case .inbox: return "Inbox"
        case .upcoming: return "Upcoming"
        case .all: return "All Tasks"
        }
    }

    var shortTitle: String {
        switch self {
        case .today: return "To-do"
        case .inbox: return "Inbox"
        case .upcoming: return "Next"
        case .all: return "All"
        }
    }

    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .inbox: return "tray.fill"
        case .upcoming: return "calendar"
        case .all: return "tray.full.fill"
        }
    }

    var tint: Color {
        switch self {
        case .today: return CueInColors.accentFixed
        case .inbox: return CueInColors.textSecondary
        case .upcoming: return CueInColors.accentFocus
        case .all: return CueInColors.accentRoutine
        }
    }

    var listKeyPrefix: String {
        switch self {
        case .today: return "tasks-page:today"
        case .inbox: return "tasks-page:inbox"
        case .upcoming: return "tasks-page:upcoming"
        case .all: return "tasks-page:all"
        }
    }
}

struct TaskDraftDefaults: Hashable {
    var fieldID: UUID?
    var projectID: UUID?
    var scheduledDate: Date?
    var dueDate: Date?
    var status: TaskStatus?
    var priority: TaskPriority?

    init(
        fieldID: UUID? = nil,
        projectID: UUID? = nil,
        scheduledDate: Date? = nil,
        dueDate: Date? = nil,
        status: TaskStatus? = nil,
        priority: TaskPriority? = nil
    ) {
        self.fieldID = fieldID
        self.projectID = projectID
        self.scheduledDate = scheduledDate
        self.dueDate = dueDate
        self.status = status
        self.priority = priority
    }

    static let inbox = TaskDraftDefaults(status: .inbox)

    static func today() -> TaskDraftDefaults {
        TaskDraftDefaults(
            scheduledDate: Calendar.current.startOfDay(for: Date()),
            status: .scheduled
        )
    }

    static func upcoming() -> TaskDraftDefaults {
        TaskDraftDefaults(
            scheduledDate: Calendar.current.date(
                byAdding: .day,
                value: 1,
                to: Calendar.current.startOfDay(for: Date())
            ),
            status: .scheduled
        )
    }

    static func project(_ project: Project) -> TaskDraftDefaults {
        TaskDraftDefaults(
            fieldID: project.fieldID,
            projectID: project.id,
            status: .inbox
        )
    }

    static func field(_ field: Field) -> TaskDraftDefaults {
        TaskDraftDefaults(fieldID: field.id, status: .inbox)
    }

    func apply(to draft: inout TaskItem) {
        if let fieldID { draft.fieldID = fieldID }
        if let projectID { draft.projectID = projectID }
        if let scheduledDate { draft.scheduledDate = scheduledDate }
        if let dueDate { draft.dueDate = dueDate }
        if let status { draft.status = status }
        if let priority { draft.priority = priority }
    }
}

enum TasksSheet: Identifiable, Hashable {
    case createTask(TaskDraftDefaults)
    case editTask(UUID)
    case createField
    case editField(UUID)
    case createProject(UUID?)
    case editProject(UUID)
    case search

    var id: String {
        switch self {
        case .createTask(let defaults):
            return "createTask:\(defaults.fieldID?.uuidString ?? "none"):\(defaults.projectID?.uuidString ?? "none"):\(defaults.scheduledDate?.timeIntervalSince1970 ?? -1)"
        case .editTask(let id):
            return "editTask:\(id.uuidString)"
        case .createField:
            return "createField"
        case .editField(let id):
            return "editField:\(id.uuidString)"
        case .createProject(let fieldID):
            return "createProject:\(fieldID?.uuidString ?? "none")"
        case .editProject(let id):
            return "editProject:\(id.uuidString)"
        case .search:
            return "search"
        }
    }
}

struct FieldRoute: Hashable { let id: UUID }
struct ProjectRoute: Hashable { let id: UUID }
