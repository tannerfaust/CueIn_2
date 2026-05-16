import Foundation

// MARK: - AntiTodoTimeRule

/// Optional **clock rule** for when an avoidance applies (local time). This is not a task “due date”:
/// it defines a daily window where you intend **extra** vigilance—e.g. no work email before 10:00,
/// or no doomscroll after 22:00.
struct AntiTodoTimeRule: Codable, Equatable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        /// Avoid this behavior from midnight until the given clock time (exclusive at the boundary).
        case notBefore
        /// Avoid this behavior from the given clock time through the end of the day.
        case notAfter
    }

    enum DayScope: String, Codable, CaseIterable {
        case everyDay
        case weekdays
        case weekends
    }

    var kind: Kind
    /// Minutes from local midnight, `0 ... 24*60-1` (we clamp on save).
    var minuteOfDay: Int
    var dayScope: DayScope

    init(kind: Kind, minuteOfDay: Int, dayScope: DayScope = .everyDay) {
        self.kind = kind
        self.minuteOfDay = Self.clampedMinuteOfDay(minuteOfDay)
        self.dayScope = dayScope
    }

    static func clampedMinuteOfDay(_ raw: Int) -> Int {
        min(max(raw, 0), 24 * 60 - 1)
    }

    /// Human-readable one-liner for list rows (includes day scope + time).
    func summaryLine(locale: Locale = .current) -> String {
        let day = dayScope.label
        let time = Self.formatTime(minuteOfDay: minuteOfDay, locale: locale)
        switch kind {
        case .notBefore:
            return "\(day) · Avoid until \(time)"
        case .notAfter:
            return "\(day) · Avoid from \(time)"
        }
    }

    /// `true` when ``dayScope`` includes this calendar day.
    func includesCalendarDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        switch dayScope {
        case .everyDay:
            return true
        case .weekdays:
            return (2...6).contains(weekday)
        case .weekends:
            return weekday == 1 || weekday == 7
        }
    }

    /// `true` when the rule is in effect **right now** (local clock + day scope).
    func isActiveNow(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard includesCalendarDay(date, calendar: calendar) else { return false }
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let nowMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        switch kind {
        case .notBefore:
            return nowMinutes < minuteOfDay
        case .notAfter:
            return nowMinutes >= minuteOfDay
        }
    }

    static func minuteOfDay(for date: Date, calendar: Calendar = .current) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return clampedMinuteOfDay((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
    }

    static func dateForPicker(minuteOfDay: Int, referenceNow: Date = Date(), calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: referenceNow)
        let clamped = clampedMinuteOfDay(minuteOfDay)
        return calendar.date(byAdding: .minute, value: clamped, to: start) ?? referenceNow
    }

    private static func formatTime(minuteOfDay: Int, locale: Locale) -> String {
        let cal = Calendar(identifier: .gregorian)
        var base = cal.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? Date()
        base = cal.date(byAdding: .minute, value: clampedMinuteOfDay(minuteOfDay), to: base) ?? base
        return base.formatted(.dateTime.hour().minute().locale(locale))
    }
}

fileprivate extension AntiTodoTimeRule.DayScope {
    var label: String {
        switch self {
        case .everyDay: return "Every day"
        case .weekdays: return "Weekdays"
        case .weekends: return "Weekends"
        }
    }
}

// MARK: - AntiTodoItem

struct AntiTodoItem: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String
    var createdAt: Date
    /// Optional local clock rule; `nil` means “all day, every day” in your head—no automatic schedule.
    var timeRule: AntiTodoTimeRule?

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(), timeRule: AntiTodoTimeRule? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.timeRule = timeRule
    }

    /// Secondary line for rows; `nil` if there is no time rule.
    func scheduleCaption(locale: Locale = .current) -> String? {
        timeRule?.summaryLine(locale: locale)
    }

    /// Whether the rule marks “extra care” **right now** (for a subtle row badge).
    func scheduleIsActiveNow(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        timeRule?.isActiveNow(at: date, calendar: calendar) ?? false
    }
}
