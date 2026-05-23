import Foundation

protocol SupabaseSyncRecord: Codable {
    var id: UUID { get }
    var userID: UUID { get set }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
    var syncVersion: Int64 { get set }
}

struct ProfileDTO: SupabaseSyncRecord {
    var id: UUID
    var userID: UUID {
        get { id }
        set { id = newValue }
    }
    var displayName: String?
    var avatarURL: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
    }
}

struct FieldDTO: SupabaseSyncRecord {
    var id: UUID
    var userID: UUID
    var name: String
    var summary: String
    var iconName: String
    var colorHex: Int64
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case summary
        case iconName = "icon_name"
        case colorHex = "color_hex"
        case isArchived = "is_archived"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
    }
}

struct ProjectDTO: SupabaseSyncRecord {
    var id: UUID
    var userID: UUID
    var fieldID: UUID?
    var name: String
    var summary: String
    var iconName: String
    var status: String
    var targetDate: Date?
    var colorHexOverride: Int64?
    var externalSource: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case fieldID = "field_id"
        case name
        case summary
        case iconName = "icon_name"
        case status
        case targetDate = "target_date"
        case colorHexOverride = "color_hex_override"
        case externalSource = "external_source"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
    }
}

struct TaskDTO: SupabaseSyncRecord {
    var id: UUID
    var userID: UUID
    var fieldID: UUID?
    var projectID: UUID?
    var title: String
    var notes: String
    var tags: [String]
    var executionType: String?
    var estimatedMinutes: Int?
    var priority: String
    var scheduledDate: Date?
    var dueDate: Date?
    var recurrence: String
    var status: String
    var completedAt: Date?
    var subtasks: [TaskSubtask]
    var savesToArchive: Bool
    var externalSource: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case fieldID = "field_id"
        case projectID = "project_id"
        case title
        case notes
        case tags
        case executionType = "execution_type"
        case estimatedMinutes = "estimated_minutes"
        case priority
        case scheduledDate = "scheduled_date"
        case dueDate = "due_date"
        case recurrence
        case status
        case completedAt = "completed_at"
        case subtasks
        case savesToArchive = "saves_to_archive"
        case externalSource = "external_source"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
    }
}

struct GoalDTO: SupabaseSyncRecord {
    var id: UUID
    var userID: UUID
    var title: String
    var why: String
    var successMetric: String
    var notes: String
    var iconName: String
    var colorHex: Int64
    var status: String
    var targetDate: Date?
    var stages: [GoalStage]
    var canvas: [String: String]
    var reviewEntries: [String]
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title
        case why
        case successMetric = "success_metric"
        case notes
        case iconName = "icon_name"
        case colorHex = "color_hex"
        case status
        case targetDate = "target_date"
        case stages
        case canvas
        case reviewEntries = "review_entries"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
    }
}

struct ScheduleRecordDTO: SupabaseSyncRecord {
    var id: UUID
    var userID: UUID
    var kind: String
    var recordDate: Date?
    var payload: [String: String]
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case kind
        case recordDate = "record_date"
        case payload
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
    }
}

struct AppLayoutSettingDTO: SupabaseSyncRecord {
    var id: UUID
    var userID: UUID
    var key: String
    var payload: [String: String]
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case key
        case payload
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
    }
}
