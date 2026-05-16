import Foundation

// MARK: - MeasureKind

/// How a tracker is logged and aggregated.
enum MeasureKind: String, Codable, CaseIterable, Identifiable {
    case count
    case scale
    case flag
    case duration

    var id: String { rawValue }

    var pickerLabel: String {
        switch self {
        case .count: return "Count (+/−)"
        case .scale: return "Scale (1–N)"
        case .flag: return "Yes / No"
        case .duration: return "Duration (minutes)"
        }
    }
}

// MARK: - MeasureValue

/// A single logged value; case must match the definition’s ``MeasureKind``.
enum MeasureValue: Codable, Equatable, Hashable {
    case count(Int)
    case scale(Int)
    case flag(Bool)
    case duration(Int)

    func matches(kind: MeasureKind) -> Bool {
        switch (self, kind) {
        case (.count, .count), (.scale, .scale), (.flag, .flag), (.duration, .duration):
            return true
        default:
            return false
        }
    }

    /// Default when the user has not logged yet (UI may still show controls).
    static func baseline(for kind: MeasureKind, scaleMin: Int, scaleMax: Int) -> MeasureValue {
        switch kind {
        case .count: return .count(0)
        case .scale: return .scale(scaleMin)
        case .flag: return .flag(false)
        case .duration: return .duration(0)
        }
    }
}

// MARK: - MeasureDefinition

struct MeasureDefinition: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String
    var iconSystemName: String
    var kind: MeasureKind
    /// Used when ``kind`` is ``.scale`` (inclusive).
    var scaleMin: Int
    var scaleMax: Int
    var createdAt: Date
    var sortIndex: Int
    /// Optional daily target for counts (e.g. 8 glasses of water).
    var dailyTarget: Int?
    /// Optional link to a task for context (resolved at display time).
    var relatedTaskID: UUID?
    /// Optional link to a goal.
    var relatedGoalID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        iconSystemName: String,
        kind: MeasureKind,
        scaleMin: Int = 1,
        scaleMax: Int = 5,
        createdAt: Date = Date(),
        sortIndex: Int = 0,
        dailyTarget: Int? = nil,
        relatedTaskID: UUID? = nil,
        relatedGoalID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.iconSystemName = iconSystemName
        self.kind = kind
        self.scaleMin = max(0, min(scaleMin, scaleMax))
        self.scaleMax = max(self.scaleMin, scaleMax)
        self.createdAt = createdAt
        self.sortIndex = sortIndex
        self.dailyTarget = dailyTarget
        self.relatedTaskID = relatedTaskID
        self.relatedGoalID = relatedGoalID
    }

    func clampedScale(_ raw: Int) -> Int {
        min(max(raw, scaleMin), scaleMax)
    }
}

// MARK: - MeasureLogEntry

struct MeasureLogEntry: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var definitionID: UUID
    /// Local-calendar day key `yyyy-MM-dd` from ``Calendar.measureDayKey(for:)``.
    var dayKey: String
    var value: MeasureValue
    var updatedAt: Date

    init(id: UUID = UUID(), definitionID: UUID, dayKey: String, value: MeasureValue, updatedAt: Date = Date()) {
        self.id = id
        self.definitionID = definitionID
        self.dayKey = dayKey
        self.value = value
        self.updatedAt = updatedAt
    }
}

// MARK: - Calendar + day keys

extension Calendar {
    /// Stable local day id for persistence and charts.
    func measureDayKey(for date: Date) -> String {
        let start = startOfDay(for: date)
        let y = component(.year, from: start)
        let m = component(.month, from: start)
        let d = component(.day, from: start)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    func measureDate(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    func measureShiftDays(_ delta: Int, from sourceDate: Date) -> Date {
        date(byAdding: .day, value: delta, to: startOfDay(for: sourceDate)) ?? sourceDate
    }
}

// MARK: - Templates

struct MeasureTemplate: Identifiable, Equatable {
    let id: String
    let title: String
    let iconSystemName: String
    let kind: MeasureKind
    let scaleMin: Int
    let scaleMax: Int
    let dailyTarget: Int?

    static let catalog: [MeasureTemplate] = [
        MeasureTemplate(id: "coffee", title: "Coffee", iconSystemName: "cup.and.saucer.fill", kind: .count, scaleMin: 1, scaleMax: 5, dailyTarget: nil),
        MeasureTemplate(id: "water", title: "Water", iconSystemName: "drop.fill", kind: .count, scaleMin: 1, scaleMax: 5, dailyTarget: 8),
        MeasureTemplate(id: "mood", title: "Mood", iconSystemName: "face.smiling", kind: .scale, scaleMin: 1, scaleMax: 5, dailyTarget: nil),
        MeasureTemplate(id: "sleep", title: "Sleep", iconSystemName: "moon.zzz.fill", kind: .duration, scaleMin: 1, scaleMax: 5, dailyTarget: nil),
        MeasureTemplate(id: "energy", title: "Energy", iconSystemName: "bolt.fill", kind: .scale, scaleMin: 1, scaleMax: 5, dailyTarget: nil),
        MeasureTemplate(id: "exercise", title: "Exercise", iconSystemName: "figure.run", kind: .flag, scaleMin: 1, scaleMax: 5, dailyTarget: nil),
        MeasureTemplate(id: "meditate", title: "Meditation", iconSystemName: "brain.head.profile", kind: .flag, scaleMin: 1, scaleMax: 5, dailyTarget: nil),
        MeasureTemplate(id: "read", title: "Reading", iconSystemName: "book.fill", kind: .duration, scaleMin: 1, scaleMax: 5, dailyTarget: nil),
        MeasureTemplate(id: "walk", title: "Walk", iconSystemName: "figure.walk", kind: .duration, scaleMin: 1, scaleMax: 5, dailyTarget: nil),
    ]
}
