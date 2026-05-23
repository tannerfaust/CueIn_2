import Foundation
import Observation

// MARK: - AntiTodoStore

@MainActor
@Observable
final class AntiTodoStore {
    static let shared = AntiTodoStore()

    private static let storageKey = "cuein.antiTodo.items.v1"

    private(set) var items: [AntiTodoItem] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func add(_ item: AntiTodoItem) {
        AppLogger.shared.log("AntiTodoStore: Adding item '\(item.title)'", category: .database)
        items.insert(item, at: 0)
        save()
    }

    func update(_ item: AntiTodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        AppLogger.shared.log("AntiTodoStore: Updating item '\(item.title)'", category: .database)
        items[index] = item
        save()
    }

    func delete(id: UUID) {
        let deletedItem = items.first { $0.id == id }
        AppLogger.shared.log("AntiTodoStore: Deleting item ID: \(id) ('\(deletedItem?.title ?? "unknown")')", category: .database)
        items.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
        AppLogger.shared.log("AntiTodoStore: Clearing all anti-todo items", category: .database)
        items.removeAll()
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            items = []
            return
        }
        do {
            items = try JSONDecoder().decode([AntiTodoItem].self, from: data)
        } catch {
            AppLogger.shared.error(error, message: "AntiTodoStore: Failed to decode stored anti-todo items")
            items = []
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
