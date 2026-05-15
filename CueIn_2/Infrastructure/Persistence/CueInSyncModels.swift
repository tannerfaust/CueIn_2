import Foundation
import SwiftData

@Model
final class LocalSyncRecord {
    @Attribute(.unique) var localKey: String
    var tableName: String
    var recordID: UUID
    var userID: UUID
    var payloadData: Data
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64
    var lastSyncedAt: Date?

    init(
        tableName: String,
        recordID: UUID,
        userID: UUID,
        payloadData: Data,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        syncVersion: Int64 = 1,
        lastSyncedAt: Date? = nil
    ) {
        self.localKey = "\(tableName):\(recordID.uuidString)"
        self.tableName = tableName
        self.recordID = recordID
        self.userID = userID
        self.payloadData = payloadData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.syncVersion = syncVersion
        self.lastSyncedAt = lastSyncedAt
    }
}

@Model
final class LocalSyncMutation {
    @Attribute(.unique) var id: UUID
    var tableName: String
    var recordID: UUID
    var operationRawValue: String
    var payloadData: Data?
    var createdAt: Date
    var attempts: Int
    var lastError: String?

    init(
        id: UUID = UUID(),
        tableName: String,
        recordID: UUID,
        operation: LocalSyncMutationOperation,
        payloadData: Data?,
        createdAt: Date = Date(),
        attempts: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.tableName = tableName
        self.recordID = recordID
        self.operationRawValue = operation.rawValue
        self.payloadData = payloadData
        self.createdAt = createdAt
        self.attempts = attempts
        self.lastError = lastError
    }

    var operation: LocalSyncMutationOperation {
        LocalSyncMutationOperation(rawValue: operationRawValue) ?? .upsert
    }
}

enum LocalSyncMutationOperation: String, Codable {
    case upsert
    case softDelete
}

enum CueInModelContainerFactory {
    static let schema = Schema([
        LocalSyncRecord.self,
        LocalSyncMutation.self
    ])

    @MainActor
    static func makeModelContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Unable to create CueIn SwiftData container: \(error)")
        }
    }
}

