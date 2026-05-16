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
        items.insert(item, at: 0)
        save()
    }

    func update(_ item: AntiTodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        save()
    }

    func delete(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
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
            items = []
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
