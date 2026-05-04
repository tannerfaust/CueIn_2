import Foundation

/// Shared short clock formatting. Prefer this over ad-hoc `DateFormatter` in view code.
/// Uses one cached 24h formatter (matches previous `HH:mm` call sites).
enum CueInTimeFormat {
    private static let hourMinuteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = .autoupdatingCurrent
        return f
    }()

    static func hourMinute(_ date: Date) -> String {
        hourMinuteFormatter.string(from: date)
    }
}
