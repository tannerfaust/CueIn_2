import Foundation
import Observation

// MARK: - DevNotebookStore

@MainActor
@Observable
final class DevNotebookStore {
    static let shared = DevNotebookStore()

    private static let storageKey = "cuein.devNotebook.entries.v1"

    private(set) var entries: [DevNotebookEntry] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func add(_ entry: DevNotebookEntry) {
        entries.insert(entry, at: 0)
        save()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            guard entries.indices.contains(index) else { continue }
            entries.remove(at: index)
        }
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    func entries(filter: DevNotebookFilter) -> [DevNotebookEntry] {
        switch filter {
        case .all: return entries
        case .kind(let k): return entries.filter { $0.kind == k }
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            entries = []
            return
        }
        do {
            entries = try JSONDecoder().decode([DevNotebookEntry].self, from: data)
        } catch {
            entries = []
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

// MARK: - Filter

enum DevNotebookFilter: Equatable, Hashable {
    case all
    case kind(DevNotebookEntryKind)
}
