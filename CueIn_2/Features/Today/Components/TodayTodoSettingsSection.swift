import SwiftUI

// MARK: - TodayTodoSettingsSection
/// All To-do view appearance controls (task block designs, page chrome, row metadata, density).

struct TodayTodoSettingsSection: View {

    @AppStorage(TodayDisplayPreferences.todoTaskBlockStyle) private var taskBlockStyleRaw
        = TodayDisplayPreferences.TodoTaskBlockStyle.listClassic.rawValue
    @AppStorage(TodayDisplayPreferences.todoRowDensity) private var rowDensityRaw
        = TodayDisplayPreferences.TodoRowDensity.regular.rawValue

    @AppStorage(TodayDisplayPreferences.todoViewShowInfoBlock) private var showSummaryCard = true
    @AppStorage(TodayDisplayPreferences.todoSummaryPlacement) private var summaryPlacementRaw
        = TodayDisplayPreferences.TodoSummaryPlacement.inList.rawValue
    @AppStorage(TodayDisplayPreferences.todoChromeSummaryMetric) private var todoChromeSummaryMetricRaw
        = TodayDisplayPreferences.TodoChromeSummaryMetric.openAndPlanned.rawValue
    @AppStorage(TodayDisplayPreferences.todoSummaryShowPlannedTime) private var summaryShowPlannedTime = true
    @AppStorage(TodayDisplayPreferences.todoSummaryShowMetricPills) private var summaryShowMetricPills = true

    @AppStorage(TodayDisplayPreferences.todoShowCompletedSection) private var showCompletedSection = true
    @AppStorage(TodayDisplayPreferences.todoShowSectionCountBadge) private var showSectionCountBadge = true
    @AppStorage(TodayDisplayPreferences.todoShowEmptyStateMessage) private var showEmptyStateMessage = true

    @AppStorage(TodayDisplayPreferences.todoRowShowCheckbox) private var rowShowCheckbox = true
    @AppStorage(TodayDisplayPreferences.todoRowShowPriorityIcon) private var rowShowPriorityIcon = true
    @AppStorage(TodayDisplayPreferences.todoRowShowOverdueIcon) private var rowShowOverdueIcon = true
    @AppStorage(TodayDisplayPreferences.todoRowShowProjectOrFieldPill) private var rowShowProjectOrFieldPill = true
    @AppStorage(TodayDisplayPreferences.todoRowProjectOrFieldPillIconOnly) private var rowProjectOrFieldPillIconOnly = false
    @AppStorage(TodayDisplayPreferences.todoRowShowPlannedMinutes) private var rowShowPlannedMinutes = false
    @AppStorage(TodayDisplayPreferences.todoRowShowDueDate) private var rowShowDueDate = false
    @AppStorage(TodayDisplayPreferences.todoRowShowTags) private var rowShowTags = false
    @AppStorage(TodayDisplayPreferences.todoRowShowNotesPreview) private var rowShowNotesPreview = false
    @AppStorage(TodayDisplayPreferences.todoRowShowLeadingFieldAccent) private var rowShowLeadingFieldAccent = false

    @AppStorage(TodayDisplayPreferences.todoRowShowInProgressDetails) private var rowShowInProgressDetails = true
    @AppStorage(TodayDisplayPreferences.todoRowShowWorkTypeChip) private var rowShowWorkTypeChip = true
    @AppStorage(TodayDisplayPreferences.todoRowShowSubtasks) private var rowShowSubtasks = true

    private var blockStyle: TodayDisplayPreferences.TodoTaskBlockStyle {
        TodayDisplayPreferences.migratedTodoTaskBlockStyle(from: taskBlockStyleRaw)
    }

    private var summaryPlacement: TodayDisplayPreferences.TodoSummaryPlacement {
        TodayDisplayPreferences.migratedTodoSummaryPlacement(from: summaryPlacementRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.lg) {
            appearanceCard
            pageCard
            rowCard
            activeTaskCard
        }
    }

    private var appearanceCard: some View {
        CueInEditorSettingsCard(title: "Appearance") {
            VStack(alignment: .leading, spacing: CueInSpacing.md) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: CueInSpacing.sm),
                        GridItem(.flexible(), spacing: CueInSpacing.sm)
                    ],
                    spacing: CueInSpacing.sm
                ) {
                    ForEach(TodayDisplayPreferences.TodoTaskBlockStyle.allCases) { style in
                        blockStyleCell(style)
                    }
                }

                Picker("Density", selection: $rowDensityRaw) {
                    ForEach(TodayDisplayPreferences.TodoRowDensity.allCases) { d in
                        Text(d.title).tag(d.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var pageCard: some View {
        CueInEditorSettingsCard(title: "Page") {
            VStack(spacing: 0) {
                settingsToggleRow(icon: "rectangle.portrait.topthird.inset.filled", title: "Show summary", isOn: $showSummaryCard)

                if showSummaryCard {
                    settingsDivider
                    summaryPlacementSegment
                    if summaryPlacement == .inList {
                        settingsDivider
                        settingsToggleRow(icon: "clock", title: "Planned time (in list)", isOn: $summaryShowPlannedTime)
                        settingsDivider
                        settingsToggleRow(icon: "chart.bar.xaxis", title: "Metric pills (in list)", isOn: $summaryShowMetricPills)
                    }
                    if summaryPlacement == .inChrome {
                        settingsDivider
                        chromeSummaryMetricPicker
                    }
                }

                settingsDivider
                settingsToggleRow(icon: "checkmark.circle", title: "Done section", isOn: $showCompletedSection)
                settingsDivider
                settingsToggleRow(icon: "number", title: "Section counts", isOn: $showSectionCountBadge)
                settingsDivider
                settingsToggleRow(icon: "tray", title: "Empty state tips", isOn: $showEmptyStateMessage)
            }
        }
    }

    private var summaryPlacementSegment: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            Text("Summary placement")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)
                .padding(.leading, 44)

            Picker("Summary placement", selection: $summaryPlacementRaw) {
                ForEach(TodayDisplayPreferences.TodoSummaryPlacement.allCases) { p in
                    Text(p.title).tag(p.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, CueInSpacing.md)
            .padding(.vertical, CueInSpacing.sm)
        }
    }

    private var chromeSummaryMetricPicker: some View {
        HStack(spacing: CueInSpacing.sm) {
            Image(systemName: "capsule.portrait")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CueInColors.textPrimary)
                .frame(width: 30, height: 30)
                .background(CueInColors.surfaceSecondary.opacity(0.58), in: Circle())

            Text("Top bar shows")
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textPrimary)

            Spacer(minLength: CueInSpacing.sm)

            Picker("Top bar summary", selection: $todoChromeSummaryMetricRaw) {
                ForEach(TodayDisplayPreferences.TodoChromeSummaryMetric.allCases) { m in
                    Text(m.title).tag(m.rawValue)
                }
            }
            .pickerStyle(.menu)
            .tint(CueInColors.accentFocus)
        }
        .padding(.vertical, 9)
    }

    private var rowCard: some View {
        CueInEditorSettingsCard(title: "Task rows") {
            VStack(spacing: 0) {
                settingsToggleRow(icon: "circle", title: "Status control", isOn: $rowShowCheckbox)
                settingsDivider
                settingsToggleRow(icon: "exclamationmark.2", title: "Priority", isOn: $rowShowPriorityIcon)
                settingsDivider
                settingsToggleRow(icon: "exclamationmark.circle", title: "Overdue alert", isOn: $rowShowOverdueIcon)
                settingsDivider
                settingsToggleRow(icon: "folder", title: "Project / field pill", isOn: $rowShowProjectOrFieldPill)
                settingsDivider
                settingsToggleRow(icon: "circle.grid.2x1", title: "Icon-only pill", isOn: $rowProjectOrFieldPillIconOnly)
                    .disabled(!rowShowProjectOrFieldPill)
                    .opacity(rowShowProjectOrFieldPill ? 1 : 0.42)
                settingsDivider
                settingsToggleRow(icon: "timer", title: "Planned time", isOn: $rowShowPlannedMinutes)
                settingsDivider
                settingsToggleRow(icon: "calendar", title: "Due date", isOn: $rowShowDueDate)
                settingsDivider
                settingsToggleRow(icon: "tag", title: "Tags", isOn: $rowShowTags)
                settingsDivider
                settingsToggleRow(icon: "text.alignleft", title: "Notes preview", isOn: $rowShowNotesPreview)
                settingsDivider
                settingsToggleRow(icon: "paintbrush", title: "Field accent", isOn: $rowShowLeadingFieldAccent)
            }
        }
    }

    private var activeTaskCard: some View {
        CueInEditorSettingsCard(title: "Active task") {
            VStack(spacing: 0) {
                settingsToggleRow(icon: "arrow.down.right.and.arrow.up.left", title: "Expanded active task", isOn: $rowShowInProgressDetails)
                settingsDivider
                settingsToggleRow(icon: "brain.head.profile", title: "Work type", isOn: $rowShowWorkTypeChip)
                    .disabled(!rowShowInProgressDetails)
                    .opacity(rowShowInProgressDetails ? 1 : 0.42)
                settingsDivider
                settingsToggleRow(icon: "checklist", title: "Subtasks", isOn: $rowShowSubtasks)
                    .disabled(!rowShowInProgressDetails)
                    .opacity(rowShowInProgressDetails ? 1 : 0.42)
            }
        }
    }

    private func blockStyleCell(_ style: TodayDisplayPreferences.TodoTaskBlockStyle) -> some View {
        let selected = style == blockStyle
        return Button {
            taskBlockStyleRaw = style.rawValue
        } label: {
            HStack(spacing: CueInSpacing.sm) {
                Image(systemName: style.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? CueInColors.textPrimary : CueInColors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(CueInColors.surfacePrimary.opacity(selected ? 0.72 : 0.42), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(style.title)
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                        .lineLimit(1)
                    Text(style.shortSettingsLabel)
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CueInSpacing.sm)
            .frame(height: 58)
            .background(CueInColors.surfaceSecondary.opacity(selected ? 0.76 : 0.46), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        selected ? CueInColors.textPrimary.opacity(0.42) : CueInColors.cardBorder.opacity(0.55),
                        lineWidth: selected ? 1.2 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var settingsDivider: some View {
        Divider()
            .background(CueInColors.divider.opacity(0.55))
            .padding(.leading, 44)
    }

    private func settingsToggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
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

private extension TodayDisplayPreferences.TodoTaskBlockStyle {
    var shortSettingsLabel: String {
        switch self {
        case .listClassic: return "Dividers"
        case .frames: return "Soft blocks"
        }
    }
}

#Preview {
    ScrollView {
        TodayTodoSettingsSection()
            .padding()
    }
    .background(CueInColors.background)
    .cueInPreferredColorScheme()
}
