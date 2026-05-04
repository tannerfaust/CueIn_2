import SwiftUI

// MARK: - TodayTodoSettingsSection
/// All To-do view appearance controls (task block designs, page chrome, row metadata, density).

struct TodayTodoSettingsSection: View {

    @AppStorage(TodayDisplayPreferences.todoTaskBlockStyle) private var taskBlockStyleRaw
        = TodayDisplayPreferences.TodoTaskBlockStyle.listClassic.rawValue
    @AppStorage(TodayDisplayPreferences.todoRowDensity) private var rowDensityRaw
        = TodayDisplayPreferences.TodoRowDensity.regular.rawValue

    @AppStorage(TodayDisplayPreferences.todoViewShowInfoBlock) private var showSummaryCard = true
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

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.lg) {
            previewCard
            appearanceCard
            pageCard
            rowCard
            activeTaskCard
        }
    }

    private var previewCard: some View {
        CueInEditorSettingsCard(title: "Preview") {
            VStack(alignment: .leading, spacing: CueInSpacing.md) {
                HStack(spacing: CueInSpacing.sm) {
                    Image(systemName: blockStyle.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CueInColors.textPrimary)
                        .frame(width: 34, height: 34)
                        .cueInEditorGlassCapsule()

                    VStack(alignment: .leading, spacing: 2) {
                        Text(blockStyle.title)
                            .font(CueInTypography.bodyMedium)
                            .foregroundStyle(CueInColors.textPrimary)
                        Text(currentSummary)
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: CueInSpacing.sm)
                }

                VStack(spacing: 0) {
                    previewTaskRow(title: "Finish API integration", meta: previewMeta, selected: true)
                    Divider()
                        .background(CueInColors.divider.opacity(0.55))
                        .padding(.leading, rowShowCheckbox ? 44 : 12)
                    previewTaskRow(title: "Write launch notes", meta: "CueIn · 20m", selected: false)
                }
                .padding(.horizontal, CueInSpacing.sm)
                .padding(.vertical, CueInSpacing.xs)
                .background(CueInColors.surfaceSecondary.opacity(0.50), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
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
                settingsToggleRow(icon: "rectangle.portrait.topthird.inset.filled", title: "Summary card", isOn: $showSummaryCard)
                settingsDivider
                settingsToggleRow(icon: "clock", title: "Planned time", isOn: $summaryShowPlannedTime)
                    .disabled(!showSummaryCard)
                    .opacity(showSummaryCard ? 1 : 0.42)
                settingsDivider
                settingsToggleRow(icon: "chart.bar.xaxis", title: "Metric pills", isOn: $summaryShowMetricPills)
                    .disabled(!showSummaryCard)
                    .opacity(showSummaryCard ? 1 : 0.42)
                settingsDivider
                settingsToggleRow(icon: "checkmark.circle", title: "Done section", isOn: $showCompletedSection)
                settingsDivider
                settingsToggleRow(icon: "number", title: "Section counts", isOn: $showSectionCountBadge)
                settingsDivider
                settingsToggleRow(icon: "tray", title: "Empty state tips", isOn: $showEmptyStateMessage)
            }
        }
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

    private var currentSummary: String {
        "\(TodayDisplayPreferences.migratedTodoRowDensity(from: rowDensityRaw).title) rows · \(enabledRowSignals) row signals"
    }

    private var enabledRowSignals: Int {
        [
            rowShowCheckbox,
            rowShowPriorityIcon,
            rowShowOverdueIcon,
            rowShowProjectOrFieldPill,
            rowShowPlannedMinutes,
            rowShowDueDate,
            rowShowTags,
            rowShowNotesPreview,
            rowShowLeadingFieldAccent
        ].filter { $0 }.count
    }

    private var previewMeta: String {
        var parts: [String] = []
        if rowShowDueDate { parts.append("Due May 6") }
        if rowShowPlannedMinutes { parts.append("45m") }
        if rowShowTags { parts.append("#launch") }
        if rowShowNotesPreview { parts.append("API docs ready") }
        return parts.isEmpty ? "CueIn · Deep work" : parts.joined(separator: " · ")
    }

    private func previewTaskRow(title: String, meta: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            if rowShowLeadingFieldAccent {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(CueInColors.textSecondary.opacity(0.9))
                    .frame(width: 3, height: 34)
            }

            if rowShowCheckbox {
                Circle()
                    .strokeBorder(CueInColors.textTertiary.opacity(0.55), lineWidth: 1.4)
                    .frame(width: 18, height: 18)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CueInColors.textPrimary)
                        .lineLimit(1)
                    if rowShowPriorityIcon && selected {
                        Image(systemName: "exclamationmark.2")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(CueInColors.accentFixed)
                    }
                    if rowShowOverdueIcon && !selected {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(CueInColors.danger)
                    }
                }

                Text(meta)
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: CueInSpacing.sm)

            if rowShowProjectOrFieldPill {
                HStack(spacing: rowProjectOrFieldPillIconOnly ? 0 : 5) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CueInColors.textSecondary)
                    if !rowProjectOrFieldPillIconOnly {
                        Text("iOS App")
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textSecondary)
                    }
                }
                .padding(.horizontal, rowProjectOrFieldPillIconOnly ? 8 : 9)
                .frame(height: 26)
                .background(CueInColors.surfacePrimary.opacity(0.62), in: Capsule(style: .continuous))
            }
        }
        .padding(.vertical, TodayDisplayPreferences.migratedTodoRowDensity(from: rowDensityRaw).verticalPadding)
        .contentShape(Rectangle())
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

struct TodayTodoSettingsFloatingPreview: View {
    @AppStorage(TodayDisplayPreferences.todoTaskBlockStyle) private var taskBlockStyleRaw
        = TodayDisplayPreferences.TodoTaskBlockStyle.listClassic.rawValue
    @AppStorage(TodayDisplayPreferences.todoRowDensity) private var rowDensityRaw
        = TodayDisplayPreferences.TodoRowDensity.regular.rawValue
    @AppStorage(TodayDisplayPreferences.todoRowShowCheckbox) private var rowShowCheckbox = true
    @AppStorage(TodayDisplayPreferences.todoRowShowPriorityIcon) private var rowShowPriorityIcon = true
    @AppStorage(TodayDisplayPreferences.todoRowShowProjectOrFieldPill) private var rowShowProjectOrFieldPill = true
    @AppStorage(TodayDisplayPreferences.todoRowProjectOrFieldPillIconOnly) private var rowProjectOrFieldPillIconOnly = false
    @AppStorage(TodayDisplayPreferences.todoRowShowPlannedMinutes) private var rowShowPlannedMinutes = false
    @AppStorage(TodayDisplayPreferences.todoRowShowDueDate) private var rowShowDueDate = false
    @AppStorage(TodayDisplayPreferences.todoRowShowTags) private var rowShowTags = false

    private var blockStyle: TodayDisplayPreferences.TodoTaskBlockStyle {
        TodayDisplayPreferences.migratedTodoTaskBlockStyle(from: taskBlockStyleRaw)
    }

    private var rowDensity: TodayDisplayPreferences.TodoRowDensity {
        TodayDisplayPreferences.migratedTodoRowDensity(from: rowDensityRaw)
    }

    var body: some View {
        HStack(spacing: 10) {
            if rowShowCheckbox {
                Circle()
                    .strokeBorder(CueInColors.textTertiary.opacity(0.55), lineWidth: 1.35)
                    .frame(width: 17, height: 17)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("Finish API integration")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CueInColors.textPrimary)
                        .lineLimit(1)
                    if rowShowPriorityIcon {
                        Image(systemName: "exclamationmark.2")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(CueInColors.textSecondary)
                    }
                }

                Text(meta)
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: CueInSpacing.sm)

            if rowShowProjectOrFieldPill {
                HStack(spacing: rowProjectOrFieldPillIconOnly ? 0 : 5) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CueInColors.textSecondary)
                    if !rowProjectOrFieldPillIconOnly {
                        Text("iOS App")
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textSecondary)
                    }
                }
                .padding(.horizontal, rowProjectOrFieldPillIconOnly ? 8 : 9)
                .frame(height: 25)
                .background(CueInColors.surfacePrimary.opacity(0.64), in: Capsule(style: .continuous))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, max(7, rowDensity.verticalPadding))
        .background {
            LinearGradient(
                colors: [
                    CueInColors.surfacePrimary.opacity(0.88),
                    CueInColors.surfaceSecondary.opacity(0.74)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.55)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
    }

    private var meta: String {
        var parts: [String] = [blockStyle.title]
        if rowShowDueDate { parts.append("May 6") }
        if rowShowPlannedMinutes { parts.append("45m") }
        if rowShowTags { parts.append("#launch") }
        return parts.joined(separator: " · ")
    }
}

private extension TodayDisplayPreferences.TodoTaskBlockStyle {
    var shortSettingsLabel: String {
        switch self {
        case .listClassic: return "Clean list"
        case .cardElevated: return "Separated"
        case .minimalHairline: return "Quiet rows"
        case .insetPanel: return "Grouped"
        }
    }
}

#Preview {
    ScrollView {
        TodayTodoSettingsSection()
            .padding()
    }
    .background(CueInColors.background)
    .preferredColorScheme(.dark)
}
