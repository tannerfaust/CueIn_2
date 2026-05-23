import SwiftUI

// MARK: - TimeblockFocusModeSettingsSection

struct TimeblockFocusModeSettingsSection: View {
    @AppStorage(TodayDisplayPreferences.timeblockFocusShowBlockIcon) private var showBlockIcon = true
    @AppStorage(TodayDisplayPreferences.timeblockFocusShowNowLabel) private var showNowLabel = true
    @AppStorage(TodayDisplayPreferences.timeblockFocusShowTimeRange) private var showTimeRange = true
    @AppStorage(TodayDisplayPreferences.timeblockFocusShowProgressBar) private var showProgressBar = true
    @AppStorage(TodayDisplayPreferences.timeblockFocusShowRemainingLine) private var showRemainingLine = true
    @AppStorage(TodayDisplayPreferences.timeblockFocusShowTaskCount) private var showTaskCount = true
    @AppStorage(TodayDisplayPreferences.timeblockFocusTimerShowsSeconds) private var timerShowsSeconds = false

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.lg) {
            CueInEditorSettingsCard(title: "Timer") {
                VStack(spacing: 0) {
                    focusSettingsToggleRow(icon: "timer", title: "Show seconds", isOn: $timerShowsSeconds)
                }
            }

            CueInEditorSettingsCard(title: "Header") {
                VStack(spacing: 0) {
                    focusSettingsToggleRow(icon: "square.grid.2x2", title: "Block icon", isOn: $showBlockIcon)
                    focusSettingsDivider
                    focusSettingsToggleRow(icon: "scope", title: "\"NOW\" label", isOn: $showNowLabel)
                    focusSettingsDivider
                    focusSettingsToggleRow(icon: "clock", title: "Time range", isOn: $showTimeRange)
                }
            }

            CueInEditorSettingsCard(title: "Progress") {
                VStack(spacing: 0) {
                    focusSettingsToggleRow(icon: "chart.bar.fill", title: "Progress bar", isOn: $showProgressBar)
                    focusSettingsDivider
                    focusSettingsToggleRow(icon: "text.alignleft", title: "Time remaining line", isOn: $showRemainingLine)
                }
            }

            CueInEditorSettingsCard(title: "Tasks") {
                VStack(spacing: 0) {
                    focusSettingsToggleRow(icon: "number", title: "Done count", isOn: $showTaskCount)
                }
            }
        }
    }

    private var focusSettingsDivider: some View {
        Divider()
            .background(CueInColors.divider.opacity(0.55))
            .padding(.leading, 44)
    }

    private func focusSettingsToggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: CueInSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? CueInColors.textPrimary : CueInColors.textTertiary)
                    .frame(width: 30, height: 30)
                    .background(CueInColors.surfaceSecondary.opacity(0.58), in: Circle())

                Text(title)
                    .font(CueInTypography.body)
                    .foregroundStyle(CueInColors.textPrimary)
            }
        }
        .tint(CueInColors.accentFocus)
        .padding(.vertical, 9)
    }
}

#Preview {
    ScrollView {
        TimeblockFocusModeSettingsSection()
            .padding()
    }
    .background(CueInColors.background)
    .cueInPreferredColorScheme()
}
