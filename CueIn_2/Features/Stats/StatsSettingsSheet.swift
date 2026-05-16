import SwiftUI

// MARK: - StatsSettingsSheet
/// Stats-only preferences (wake / sleep window + which sections appear).

struct StatsSettingsSheet: View {
    @Binding var isPresented: Bool

    @AppStorage(StatsDisplayPreferences.showActivityRings) private var showActivityRings = true
    @AppStorage(StatsDisplayPreferences.showTodayProgressCard) private var showTodayProgressCard = true
    @AppStorage(StatsDisplayPreferences.showWeeklySnapshot) private var showWeeklySnapshot = false
    @AppStorage(StatsDisplayPreferences.showTimeAllocation) private var showTimeAllocation = false
    @AppStorage(StatsDisplayPreferences.showTrends) private var showTrends = false
    @AppStorage(StatsDisplayPreferences.showActivitySparkline) private var showActivitySparkline = false

    @AppStorage(StatsDisplayPreferences.dayWakeMinutes) private var dayWakeMinutes = StatsDisplayPreferences.dayWakeMinutesDefault
    @AppStorage(StatsDisplayPreferences.daySleepMinutes) private var daySleepMinutes = StatsDisplayPreferences.daySleepMinutesDefault

    var body: some View {
        CueInBottomSheet(title: "Stats settings", onDismiss: { isPresented = false }) {
            VStack(alignment: .leading, spacing: CueInSpacing.lg) {
                sectionTitle("Day window")
                Text("Used for the outer ring and “time until sleep”. Same calendar day: wake first, then sleep.")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)

                minutesPickerRow(title: "Wake", minutes: $dayWakeMinutes, isWake: true)
                minutesPickerRow(title: "Sleep", minutes: $daySleepMinutes, isWake: false)

                sectionTitle("Sections")
                Toggle("Activity rings", isOn: $showActivityRings)
                Toggle("Today task summary", isOn: $showTodayProgressCard)
                Toggle("Weekly snapshot (sample)", isOn: $showWeeklySnapshot)
                Toggle("Time allocation (sample)", isOn: $showTimeAllocation)
                Toggle("Trends (sample)", isOn: $showTrends)
                Toggle("7-day activity (sample)", isOn: $showActivitySparkline)
            }
        }
        .onChange(of: dayWakeMinutes) { _, newWake in
            dayWakeMinutes = StatsDisplayPreferences.clampWakeMinutes(newWake)
            daySleepMinutes = StatsDisplayPreferences.clampSleepMinutes(wakeMinutes: dayWakeMinutes, sleepMinutes: daySleepMinutes)
        }
        .onChange(of: daySleepMinutes) { _, newSleep in
            daySleepMinutes = StatsDisplayPreferences.clampSleepMinutes(wakeMinutes: dayWakeMinutes, sleepMinutes: newSleep)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(CueInTypography.headline)
            .foregroundStyle(CueInColors.textPrimary)
    }

    private func minutesPickerRow(title: String, minutes: Binding<Int>, isWake: Bool) -> some View {
        let dateBinding = Binding<Date>(
            get: {
                Self.dateFromMinutes(minutes.wrappedValue) ?? Date()
            },
            set: { newDate in
                let m = Self.minutesFromDate(newDate)
                if isWake {
                    minutes.wrappedValue = StatsDisplayPreferences.clampWakeMinutes(m)
                } else {
                    minutes.wrappedValue = StatsDisplayPreferences.clampSleepMinutes(wakeMinutes: dayWakeMinutes, sleepMinutes: m)
                }
            }
        )

        return HStack {
            Text(title)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textSecondary)
            Spacer()
            DatePicker("", selection: dateBinding, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "en_GB"))
        }
        .padding(.vertical, CueInSpacing.xs)
    }

    private static func minutesFromDate(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private static func dateFromMinutes(_ minutes: Int) -> Date? {
        let day = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .minute, value: minutes, to: day)
    }
}
