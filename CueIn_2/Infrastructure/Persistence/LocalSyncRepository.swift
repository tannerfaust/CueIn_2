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
        try upsertWithoutSaving(record, table: table, enqueueMutation: enqueueMutation)
        try modelContext.save()
    }

    func upsert<Record: SupabaseSyncRecord>(_ records: [Record], table: SupabaseTable, enqueueMutation: Bool) throws {
        guard !records.isEmpty else { return }
        for record in records {
            try upsertWithoutSaving(record, table: table, enqueueMutation: enqueueMutation)
        }
        try modelContext.save()
    }

    private func upsertWithoutSaving<Record: SupabaseSyncRecord>(
        _ record: Record,
        table: SupabaseTable,
        enqueueMutation: Bool
    ) throws {
        let payload = try encoder.encode(record)
        let localKey = "\(table.rawValue):\(record.id.uuidString)"
        let descriptor = FetchDescriptor<LocalSyncRecord>(
            predicate: #Predicate { $0.localKey == localKey }
        )

        var hasChanged = true
        if let existing = try modelContext.fetch(descriptor).first {
            if existing.payloadData == payload && existing.userID == record.userID && existing.deletedAt == record.deletedAt {
                hasChanged = false
            } else {
                existing.userID = record.userID
                existing.payloadData = payload
                existing.createdAt = record.createdAt
                existing.updatedAt = record.updatedAt
                existing.deletedAt = record.deletedAt
                existing.syncVersion = record.syncVersion
            }
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

        if enqueueMutation && hasChanged {
            try upsertPendingMutation(
                tableName: table.rawValue,
                recordID: record.id,
                operation: record.deletedAt == nil ? .upsert : .softDelete,
                payloadData: payload
            )
        }
    }

    func records<Record: SupabaseSyncRecord>(_ type: Record.Type, table: SupabaseTable, userID: UUID) throws -> [Record] {
        let tableName = table.rawValue
        let descriptor = FetchDescriptor<LocalSyncRecord>(
            predicate: #Predicate { $0.tableName == tableName && $0.userID == userID }
        )
        return try modelContext.fetch(descriptor).compactMap { row in
            do {
                return try decoder.decode(Record.self, from: row.payloadData)
            } catch {
                // A corrupt cached payload (e.g. schema drift across an
                // upgrade) shouldn't take the whole sync down. Log it once
                // and skip; the next remote pull will overwrite the row.
                AppLogger.shared.error(
                    error,
                    message: "Failed to decode cached \(Record.self) row id=\(row.recordID) on table=\(tableName); skipping"
                )
                return nil
            }
        }
    }

    func pendingMutations() throws -> [LocalSyncMutation] {
        var descriptor = FetchDescriptor<LocalSyncMutation>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 100
        return try modelContext.fetch(descriptor)
    }

    func hasPendingMutation(table: SupabaseTable, recordID: UUID) throws -> Bool {
        let tableName = table.rawValue
        var descriptor = FetchDescriptor<LocalSyncMutation>(
            predicate: #Predicate { $0.tableName == tableName && $0.recordID == recordID }
        )
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }

    func clearPendingMutations(for table: SupabaseTable) throws {
        let tableName = table.rawValue
        let descriptor = FetchDescriptor<LocalSyncMutation>(
            predicate: #Predicate { $0.tableName == tableName }
        )
        for mutation in try modelContext.fetch(descriptor) {
            modelContext.delete(mutation)
        }
        try modelContext.save()
    }

    func hasCachedWorkspace(for userID: UUID) throws -> Bool {
        try hasRecords(table: .fields, userID: userID)
            || hasRecords(table: .projects, userID: userID)
            || hasRecords(table: .tasks, userID: userID)
            || hasRecords(table: .goals, userID: userID)
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

    func resetLastPullDate(for table: SupabaseTable) {
        UserDefaults.standard.removeObject(forKey: lastPullKey(table))
    }

    private func lastPullKey(_ table: SupabaseTable) -> String {
        "cuein.sync.lastPull.\(table.rawValue)"
    }

    private func hasRecords(table: SupabaseTable, userID: UUID) throws -> Bool {
        let tableName = table.rawValue
        var descriptor = FetchDescriptor<LocalSyncRecord>(
            predicate: #Predicate { $0.tableName == tableName && $0.userID == userID && $0.deletedAt == nil }
        )
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }

    private func upsertPendingMutation(
        tableName: String,
        recordID: UUID,
        operation: LocalSyncMutationOperation,
        payloadData: Data
    ) throws {
        let descriptor = FetchDescriptor<LocalSyncMutation>(
            predicate: #Predicate { $0.tableName == tableName && $0.recordID == recordID }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            existing.operationRawValue = operation.rawValue
            existing.payloadData = payloadData
            existing.createdAt = Date()
            existing.attempts = 0
            existing.lastError = nil
            return
        }

        modelContext.insert(
            LocalSyncMutation(
                tableName: tableName,
                recordID: recordID,
                operation: operation,
                payloadData: payloadData
            )
        )
    }
}
