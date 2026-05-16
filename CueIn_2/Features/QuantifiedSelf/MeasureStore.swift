import Foundation
import Observation

// MARK: - MeasureStore

@MainActor
@Observable
final class MeasureStore {
    static let shared = MeasureStore()

    private static let definitionsKey = "cuein.measures.definitions.v1"
    private static let logsKey = "cuein.measures.logs.v1"

    private(set) var definitions: [MeasureDefinition] = []
    private(set) var logs: [MeasureLogEntry] = []

    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        load()
    }

    var sortedDefinitions: [MeasureDefinition] {
        definitions.sorted { a, b in
            if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
            return a.createdAt < b.createdAt
        }
    }

    func definition(id: UUID) -> MeasureDefinition? {
        definitions.first { $0.id == id }
    }

    /// Latest log for this definition on the given local day, if any.
    func log(definitionID: UUID, dayKey: String) -> MeasureLogEntry? {
        logs.last { $0.definitionID == definitionID && $0.dayKey == dayKey }
    }

    func value(definitionID: UUID, dayKey: String) -> MeasureValue? {
        log(definitionID: definitionID, dayKey: dayKey)?.value
    }

    func setValue(_ value: MeasureValue, definitionID: UUID, dayKey: String) {
        guard let def = definition(id: definitionID), value.matches(kind: def.kind) else { return }
        let normalized = normalize(value, definition: def)
        if let idx = logs.firstIndex(where: { $0.definitionID == definitionID && $0.dayKey == dayKey }) {
            var entry = logs[idx]
            entry.value = normalized
            entry.updatedAt = Date()
            logs[idx] = entry
        } else {
            logs.append(MeasureLogEntry(definitionID: definitionID, dayKey: dayKey, value: normalized))
        }
        save()
    }

    func incrementCount(definitionID: UUID, dayKey: String, delta: Int) {
        guard let def = definition(id: definitionID), def.kind == .count else { return }
        let current: Int
        if case .count(let n) = value(definitionID: definitionID, dayKey: dayKey) {
            current = n
        } else {
            current = 0
        }
        setValue(.count(max(0, current + delta)), definitionID: definitionID, dayKey: dayKey)
    }

    func addDefinition(_ definition: MeasureDefinition) {
        var def = definition
        let nextIndex = (definitions.map(\.sortIndex).max() ?? -1) + 1
        def.sortIndex = nextIndex
        definitions.append(def)
        save()
    }

    func updateDefinition(_ definition: MeasureDefinition) {
        guard let idx = definitions.firstIndex(where: { $0.id == definition.id }) else { return }
        definitions[idx] = definition
        save()
    }

    func deleteDefinition(id: UUID) {
        definitions.removeAll { $0.id == id }
        logs.removeAll { $0.definitionID == id }
        save()
    }

    func clearAll() {
        definitions = []
        logs = []
        save()
    }

    // MARK: - Sparkline (last N local days ending at `dayKey`)

    /// Normalized heights in `0...1` oldest → newest for small bar visuals.
    func sparklineNormalized(definitionID: UUID, endingDayKey: String, days: Int = 7) -> [CGFloat] {
        guard let def = definition(id: definitionID),
              let endDate = calendar.measureDate(fromDayKey: endingDayKey)
        else {
            return Array(repeating: 0.04, count: days)
        }

        var keys: [String] = []
        for offset in (0..<days).reversed() {
            let d = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: endDate)) ?? endDate
            keys.append(calendar.measureDayKey(for: d))
        }

        let raw: [CGFloat] = keys.map { key in
            guard let v = value(definitionID: definitionID, dayKey: key) else { return 0 }
            return scalarForSparkline(v, definition: def, dayKey: key)
        }

        switch def.kind {
        case .count:
            let maxV = max(raw.max() ?? 0, 1)
            return raw.map { $0 / maxV }
        case .scale:
            let span = CGFloat(max(def.scaleMax - def.scaleMin, 1))
            return raw.map { v in
                if v <= 0 { return 0.04 }
                return (v - CGFloat(def.scaleMin)) / span
            }
        case .flag:
            return raw.map { $0 > 0.5 ? 1 : 0.08 }
        case .duration:
            let maxV = max(raw.max() ?? 0, 1)
            return raw.map { $0 / maxV }
        }
    }

    private func scalarForSparkline(_ value: MeasureValue, definition: MeasureDefinition, dayKey: String) -> CGFloat {
        switch value {
        case .count(let n):
            return CGFloat(max(n, 0))
        case .scale(let s):
            return CGFloat(definition.clampedScale(s))
        case .flag(let b):
            return b ? 1 : 0
        case .duration(let m):
            return CGFloat(max(m, 0))
        }
    }

    // MARK: - Private

    private func normalize(_ value: MeasureValue, definition: MeasureDefinition) -> MeasureValue {
        switch value {
        case .count(let n):
            return .count(max(0, n))
        case .scale(let s):
            return .scale(definition.clampedScale(s))
        case .flag(let b):
            return .flag(b)
        case .duration(let m):
            return .duration(max(0, min(m, 24 * 60)))
        }
    }

    private func load() {
        if let data = defaults.data(forKey: Self.definitionsKey),
           let decoded = try? JSONDecoder().decode([MeasureDefinition].self, from: data) {
            definitions = decoded
        } else {
            definitions = []
        }

        if let data = defaults.data(forKey: Self.logsKey),
           let decoded = try? JSONDecoder().decode([MeasureLogEntry].self, from: data) {
            logs = decoded
        } else {
            logs = []
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(definitions) {
            defaults.set(data, forKey: Self.definitionsKey)
        }
        if let data = try? JSONEncoder().encode(logs) {
            defaults.set(data, forKey: Self.logsKey)
        }
    }
}
