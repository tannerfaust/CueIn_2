import Foundation
import SwiftData

@MainActor
final class LocalSyncRepository {
    private let modelContext: ModelContext
    private let encoder = JSONEncoder.cueInSyncEncoder
    private let decoder = JSONDecoder.cueInSyncDecoder

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func upsert<Record: SupabaseSyncRecord>(_ record: Record, table: SupabaseTable, enqueueMutation: Bool) throws {
        let payload = try encoder.encode(record)
        let localKey = "\(table.rawValue):\(record.id.uuidString)"
        let descriptor = FetchDescriptor<LocalSyncRecord>(
            predicate: #Predicate { $0.localKey == localKey }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            existing.userID = record.userID
            existing.payloadData = payload
            existing.createdAt = record.createdAt
            existing.updatedAt = record.updatedAt
            existing.deletedAt = record.deletedAt
            existing.syncVersion = record.syncVersion
        } else {
            modelContext.insert(
                LocalSyncRecord(
                    tableName: table.rawValue,
                    recordID: record.id,
                    userID: record.userID,
                    payloadData: payload,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt,
                    deletedAt: record.deletedAt,
                    syncVersion: record.syncVersion
                )
            )
        }

        if enqueueMutation {
            modelContext.insert(
                LocalSyncMutation(
                    tableName: table.rawValue,
                    recordID: record.id,
                    operation: record.deletedAt == nil ? .upsert : .softDelete,
                    payloadData: payload
                )
            )
        }

        try modelContext.save()
    }

    func records<Record: SupabaseSyncRecord>(_ type: Record.Type, table: SupabaseTable, userID: UUID) throws -> [Record] {
        let tableName = table.rawValue
        let descriptor = FetchDescriptor<LocalSyncRecord>(
            predicate: #Predicate { $0.tableName == tableName && $0.userID == userID }
        )
        return try modelContext.fetch(descriptor)
            .compactMap { try? decoder.decode(Record.self, from: $0.payloadData) }
    }

    func pendingMutations() throws -> [LocalSyncMutation] {
        var descriptor = FetchDescriptor<LocalSyncMutation>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 100
        return try modelContext.fetch(descriptor)
    }

    func markSynced(_ mutation: LocalSyncMutation) throws {
        modelContext.delete(mutation)
        try modelContext.save()
    }

    func markFailed(_ mutation: LocalSyncMutation, error: Error) throws {
        mutation.attempts += 1
        mutation.lastError = error.localizedDescription
        try modelContext.save()
    }

    func lastPullDate(for table: SupabaseTable) -> Date? {
        UserDefaults.standard.object(forKey: lastPullKey(table)) as? Date
    }

    func setLastPullDate(_ date: Date, for table: SupabaseTable) {
        UserDefaults.standard.set(date, forKey: lastPullKey(table))
    }

    private func lastPullKey(_ table: SupabaseTable) -> String {
        "cuein.sync.lastPull.\(table.rawValue)"
    }
}

