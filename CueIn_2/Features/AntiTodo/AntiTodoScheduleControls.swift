import SwiftUI

// MARK: - AntiTodoScheduleControls

/// Shared, minimal controls for optional **clock rules** (not task due dates).
struct AntiTodoScheduleControls: View {
    @Binding var enabled: Bool
    @Binding var kind: AntiTodoTimeRule.Kind
    @Binding var dayScope: AntiTodoTimeRule.DayScope
    @Binding var time: Date

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            Toggle("Limit by time of day", isOn: $enabled)
                .font(CueInTypography.bodyMedium)
                .foregroundStyle(CueInColors.textPrimary)
                .tint(CueInColors.danger)

            if enabled {
                VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                    Text("When it applies")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)

                    Picker("Rule kind", selection: $kind) {
                        Text("Avoid until…").tag(AntiTodoTimeRule.Kind.notBefore)
                        Text("Avoid from… onward").tag(AntiTodoTimeRule.Kind.notAfter)
                    }
                    .pickerStyle(.segmented)

                    Text(kind == .notBefore
                        ? "You’re most likely to slip before this time—hold the line until then."
                        : "You’re most likely to slip after this time—ease off once you reach it.")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    DatePicker(
                        "Time",
                        selection: $time,
                        displayedComponents: [.hourAndMinute]
                    )
                    .labelsHidden()
                    .accessibilityLabel("Time of day")
                    .tint(CueInColors.danger)

                    HStack {
                        Text("Applies on")
                            .font(CueInTypography.bodyMedium)
                            .foregroundStyle(CueInColors.textSecondary)
                        Spacer()
                        Picker("Applies on", selection: $dayScope) {
                            Text("Every day").tag(AntiTodoTimeRule.DayScope.everyDay)
                            Text("Weekdays").tag(AntiTodoTimeRule.DayScope.weekdays)
                            Text("Weekends").tag(AntiTodoTimeRule.DayScope.weekends)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(CueInColors.textPrimary)
                    }
                }
                .padding(CueInSpacing.md)
                .background(CueInColors.surfaceSecondary.opacity(0.55), in: RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                        .strokeBorder(CueInColors.danger.opacity(0.18), lineWidth: 0.5)
                }
            }
        }
    }
}
