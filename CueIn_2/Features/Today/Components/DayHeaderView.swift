import SwiftUI

// MARK: - DayHeaderView
/// One scannable block: date, day progress %, and light task stats — no greetings.

struct DayHeaderView: View {
    /// Calendar day this header describes (typically start-of-day).
    let displayDate: Date
    /// “Now” used for relative labels (Today / Tomorrow / Yesterday).
    let relativeNow: Date
    let dayProgress: Double
    let statusLine: String
    /// When false, hides the day % (e.g. formula preview before Start).
    var showsProgressPercent: Bool = true

    private var dayLine: String {
        Self.headline(for: displayDate, relativeTo: relativeNow)
    }

    /// Shared “Today / Tomorrow / Wed Apr 24” label for inline and sticky timeline headers.
    static func headline(for displayDate: Date, relativeTo relativeNow: Date) -> String {
        formatDayHeadline(displayDate: displayDate, relativeTo: relativeNow)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: CueInSpacing.sm) {
                Text(dayLine)
                    .font(CueInTypography.headline)
                    .foregroundStyle(CueInColors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: CueInSpacing.sm)

                if showsProgressPercent {
                    Text("\(Int(dayProgress * 100))%")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                        .monospacedDigit()
                }
            }

            Text(statusLine)
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.top, CueInSpacing.xs)
    }

    private static func formatDayHeadline(displayDate: Date, relativeTo now: Date) -> String {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: displayDate)
        let today = calendar.startOfDay(for: now)

        if calendar.isDate(day, inSameDayAs: today) {
            return "Today"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(day, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }

        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter.string(from: day)
    }
}
