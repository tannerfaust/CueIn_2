import Foundation

extension FieldDTO {
    init(field: Field, userID: UUID, deletedAt: Date? = nil, syncVersion: Int64 = 1) {
        self.init(
            id: field.id,
            userID: userID,
            name: field.name,
            summary: field.summary,
            iconName: field.iconName,
            colorHex: Int64(field.colorHex),
            isArchived: field.isArchived,
            createdAt: field.createdAt,
            updatedAt: field.createdAt,
            deletedAt: deletedAt,
            syncVersion: syncVersion
        )
    }

    var domainModel: Field {
        Field(
            id: id,
            name: name,
            summary: summary,
            iconName: iconName,
            colorHex: UInt(colorHex),
            createdAt: createdAt,
            isArchived: isArchived
        )
    }
}

extension ProjectDTO {
    init(project: Project, userID: UUID, deletedAt: Date? = nil, syncVersion: Int64 = 1) {
        self.init(
            id: project.id,
            userID: userID,
            fieldID: project.fieldID,
            name: project.name,
            summary: project.summary,
            iconName: project.iconName,
            status: project.status.rawValue,
            targetDate: project.targetDate,
            colorHexOverride: project.colorHexOverride.map(Int64.init),
            externalSource: project.externalSource,
            createdAt: project.createdAt,
            updatedAt: project.createdAt,
            deletedAt: deletedAt,
            syncVersion: syncVersion
        )
    }

    var domainModel: Project? {
        guard let fieldID else { return nil }
        return Project(
            id: id,
            name: name,
            summary: summary,
            iconName: iconName,
            fieldID: fieldID,
            status: Project.Status(rawValue: status) ?? .active,
            targetDate: targetDate,
            colorHexOverride: colorHexOverride.map(UInt.init),
            externalSource: externalSource,
            createdAt: createdAt
        )
    }
}

extension TaskDTO {
    init(task: TaskItem, userID: UUID, deletedAt: Date? = nil, syncVersion: Int64 = 1) {
        self.init(
            id: task.id,
            userID: userID,
            fieldID: task.fieldID,
            projectID: task.projectID,
            title: task.title,
            notes: task.notes,
            tags: task.tags,
            executionType: task.executionType?.rawValue,
            estimatedMinutes: task.estimatedMinutes,
            priority: task.priority.rawValue,
            scheduledDate: task.scheduledDate,
            dueDate: task.dueDate,
            recurrence: task.recurrence.rawValue,
            status: task.status.rawValue,
            completedAt: task.completedAt,
            subtasks: task.subtasks,
            savesToArchive: task.savesToArchive,
            externalSource: task.externalSource,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt,
            deletedAt: deletedAt,
            syncVersion: syncVersion
        )
    }

    var domainModel: TaskItem {
        TaskItem(
            id: id,
            title: title,
            notes: notes,
            fieldID: fieldID,
            projectID: projectID,
            tags: tags,
            executionType: executionType.flatMap(TaskExecutionType.init(rawValue:)),
            estimatedMinutes: estimatedMinutes,
            priority: TaskPriority(rawValue: priority) ?? .normal,
            scheduledDate: scheduledDate,
            dueDate: dueDate,
            recurrence: TaskRecurrence(rawValue: recurrence) ?? .none,
            status: TaskStatus(rawValue: status) ?? .inbox,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt,
            subtasks: subtasks,
            savesToArchive: savesToArchive,
            externalSource: externalSource
        )
    }
}

extension GoalDTO {
    init(goal: Goal, userID: UUID, deletedAt: Date? = nil, syncVersion: Int64 = 1) {
        self.init(
            id: goal.id,
            userID: userID,
            title: goal.title,
            why: goal.description,
            successMetric: "",
            notes: goal.description,
            iconName: "target",
            colorHex: 3450713,
            status: goal.status.rawValue,
            targetDate: goal.targetDate,
            stages: goal.stages,
            canvas: [:],
            reviewEntries: [],
            createdAt: goal.createdAt,
            updatedAt: goal.updatedAt,
            deletedAt: deletedAt,
            syncVersion: syncVersion
        )
    }

    var domainModel: Goal {
        Goal(
            id: id,
            title: title,
            description: notes.isEmpty ? why : notes,
            status: GoalStatus(rawValue: status) ?? .active,
            targetDate: targetDate,
            stages: stages,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
