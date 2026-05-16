import SwiftUI

// MARK: - TodaySettingsSheet
/// Single place for Today display: timeline layout & zoom (task-led) or schedule design, running line, and block fields.

struct TodaySettingsSheet: View {
    let isTaskLedMode: Bool
    @Binding var taskLedViewModeRaw: String
    @Binding var timelineLayoutModeRaw: String
    @Binding var timelineHourHeight: Double
    @Binding var scheduleDesignRaw: String
    @Binding var runningLineStyleRaw: String
    @Binding var activeBlockEmphasisRaw: String
    @Binding var runningLineSizeRaw: String
    @Binding var runningLineBarWeightRaw: String
    @Binding var runningLineFrostedCard: Bool
    @Binding var runningLineShowBlockTitle: Bool
    @Binding var runningLineShowDayPercent: Bool
    @Binding var schedulePauseBehaviorRaw: String
    @Binding var showScheduleStartTime: Bool
    @Binding var showScheduleDuration: Bool
    @Binding var showScheduleTimeRange: Bool
    @Binding var scheduleBlockTimerStyleRaw: String
    @Binding var scheduleBlockTimerShowsSeconds: Bool
    @Binding var pullsTasksFromExecutionPool: Bool
    @Binding var canvasDotsBackground: Bool
    let onDismiss: () -> Void

    @State private var showRunningLineAdvanced = false
    @State private var bindingRollback: TodaySettingsBindingRollback?
    @State private var todoAppearancePlist: Data?

    private var design: TodayDisplayPreferences.ScheduleDesign {
        TodayDisplayPreferences.migratedScheduleDesign(from: scheduleDesignRaw)
    }

    private var runningLine: TodayDisplayPreferences.RunningLineStyle {
        TodayDisplayPreferences.migratedRunningLineStyle(from: runningLineStyleRaw)
    }

    private var activeBlockEmphasis: TodayDisplayPreferences.ActiveBlockEmphasis {
        TodayDisplayPreferences.migratedActiveBlockEmphasis(from: activeBlockEmphasisRaw)
    }

    private var timelineLayoutMode: TodayDisplayPreferences.TimelineLayoutMode {
        TodayDisplayPreferences.TimelineLayoutMode(rawValue: timelineLayoutModeRaw) ?? .vertical
    }

    private var taskLedViewMode: TodayDisplayPreferences.TaskLedViewMode {
        TodayDisplayPreferences.TaskLedViewMode(rawValue: taskLedViewModeRaw) ?? .timeline
    }

    private var scheduleBlockTimerStyle: TodayDisplayPreferences.ScheduleBlockTimerStyle {
        TodayDisplayPreferences.migratedScheduleBlockTimerStyle(from: scheduleBlockTimerStyleRaw)
    }

    private var schedulePauseBehavior: TodayDisplayPreferences.SchedulePauseBehavior {
        TodayDisplayPreferences.migratedSchedulePauseBehavior(from: schedulePauseBehaviorRaw)
    }

    private func scheduleCardTitle(_ text: String) -> some View {
        Text(text)
            .font(CueInTypography.bodyMedium)
            .fontWeight(.semibold)
            .foregroundStyle(CueInColors.textPrimary)
    }

    var body: some View {
        CueInBottomSheet(
            title: taskLedViewMode == .todo ? "To-do settings" : "Settings",
            onDismiss: onDismiss,
            onEditorDiscard: {
                if let bindingRollback {
                    applyBindingRollback(bindingRollback)
                }
                TodayDisplayPreferences.restoreTodoAppearance(from: todoAppearancePlist)
            },
            editorPrincipalIcon: taskLedViewMode == .todo ? nil : "gearshape.fill",
            editorSaveForeground: taskLedViewMode == .todo ? CueInColors.textPrimary : CueInColors.accentFocus,
            floatingAccessory: nil
        ) {
            VStack(alignment: .leading, spacing: CueInSpacing.lg) {
                if isTaskLedMode {
                    if taskLedViewMode == .todo {
                        todoListSection
                    } else {
                        timelineSection
                    }
                } else {
                    scheduleSection
                }
            }
            .onAppear {
                guard bindingRollback == nil else { return }
                bindingRollback = TodaySettingsBindingRollback(
                    taskLedViewModeRaw: taskLedViewModeRaw,
                    timelineLayoutModeRaw: timelineLayoutModeRaw,
                    timelineHourHeight: timelineHourHeight,
                    scheduleDesignRaw: scheduleDesignRaw,
                    runningLineStyleRaw: runningLineStyleRaw,
                    activeBlockEmphasisRaw: activeBlockEmphasisRaw,
                    runningLineSizeRaw: runningLineSizeRaw,
                    runningLineBarWeightRaw: runningLineBarWeightRaw,
                    runningLineFrostedCard: runningLineFrostedCard,
                    runningLineShowBlockTitle: runningLineShowBlockTitle,
                    runningLineShowDayPercent: runningLineShowDayPercent,
                    schedulePauseBehaviorRaw: schedulePauseBehaviorRaw,
                    showScheduleStartTime: showScheduleStartTime,
                    showScheduleDuration: showScheduleDuration,
                    showScheduleTimeRange: showScheduleTimeRange,
                    scheduleBlockTimerStyleRaw: scheduleBlockTimerStyleRaw,
                    scheduleBlockTimerShowsSeconds: scheduleBlockTimerShowsSeconds,
                    pullsTasksFromExecutionPool: pullsTasksFromExecutionPool,
                    canvasDotsBackground: canvasDotsBackground
                )
                todoAppearancePlist = TodayDisplayPreferences.snapshotTodoAppearancePlist()
            }
        }
    }

    private func applyBindingRollback(_ r: TodaySettingsBindingRollback) {
        taskLedViewModeRaw = r.taskLedViewModeRaw
        timelineLayoutModeRaw = r.timelineLayoutModeRaw
        timelineHourHeight = r.timelineHourHeight
        scheduleDesignRaw = r.scheduleDesignRaw
        runningLineStyleRaw = r.runningLineStyleRaw
        activeBlockEmphasisRaw = r.activeBlockEmphasisRaw
        runningLineSizeRaw = r.runningLineSizeRaw
        runningLineBarWeightRaw = r.runningLineBarWeightRaw
        runningLineFrostedCard = r.runningLineFrostedCard
        runningLineShowBlockTitle = r.runningLineShowBlockTitle
        runningLineShowDayPercent = r.runningLineShowDayPercent
        schedulePauseBehaviorRaw = r.schedulePauseBehaviorRaw
        showScheduleStartTime = r.showScheduleStartTime
        showScheduleDuration = r.showScheduleDuration
        showScheduleTimeRange = r.showScheduleTimeRange
        scheduleBlockTimerStyleRaw = r.scheduleBlockTimerStyleRaw
        scheduleBlockTimerShowsSeconds = r.scheduleBlockTimerShowsSeconds
        pullsTasksFromExecutionPool = r.pullsTasksFromExecutionPool
        canvasDotsBackground = r.canvasDotsBackground
    }

    // MARK: - To-do list (task-led)

    private var todoListSection: some View {
        TodayTodoSettingsSection()
    }

    // MARK: - Timeline (task-led)

    private var timelineSection: some View {
        CueInEditorSettingsCard(title: "Timeline") {
            Text("How the execution day scrolls and how tall each hour is.")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)

            VStack(alignment: .leading, spacing: CueInSpacing.xs) {
                sectionSubheader("Layout")
                VStack(spacing: 0) {
                    choiceRow(
                        icon: "arrow.up.and.down",
                        title: "Vertical scroll",
                        subtitle: "Scroll through the day in one view",
                        isSelected: timelineLayoutMode == .vertical
                    ) {
                        timelineLayoutModeRaw = TodayDisplayPreferences.TimelineLayoutMode.vertical.rawValue
                    }
                    choiceRow(
                        icon: "arrow.left.and.right",
                        title: "Swipe days",
                        subtitle: "Page one day at a time",
                        isSelected: timelineLayoutMode == .paged
                    ) {
                        timelineLayoutModeRaw = TodayDisplayPreferences.TimelineLayoutMode.paged.rawValue
                    }
                }
            }

            VStack(alignment: .leading, spacing: CueInSpacing.xs) {
                sectionSubheader("Zoom")
                VStack(spacing: 0) {
                    ForEach(TodayDisplayPreferences.timelineScales) { scale in
                        choiceRow(
                            icon: "arrow.up.left.and.arrow.down.right",
                            title: scale.label,
                            subtitle: nil,
                            isSelected: isScaleSelected(scale.hourHeight)
                        ) {
                            timelineHourHeight = scale.hourHeight
                        }
                    }
                }
            }
        }
    }

    // MARK: - Schedule (formula / schedule mode)

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.lg) {
            CueInEditorSettingsCard(title: "Block style") {
                Text("Choose how schedule rows look. Gestures and order stay the same for every style.")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: CueInSpacing.sm), GridItem(.flexible(), spacing: CueInSpacing.sm)],
                    spacing: CueInSpacing.sm
                ) {
                    ForEach(TodayDisplayPreferences.ScheduleDesign.allCases) { d in
                        blockDesignCell(d)
                    }
                }

                Text(design.subtitle)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .padding(.top, 2)
            }

            CueInEditorSettingsCard(title: "Block timer") {
                scheduleTimerGroupContent
            }

            CueInEditorSettingsCard(title: "Day progress") {
                dayProgressGroupContent
            }

            CueInEditorSettingsCard(title: "Pause behavior") {
                pauseBehaviorGroupContent
            }

            CueInEditorSettingsCard(title: "On each block") {
                blockFieldTogglesGroupContent
            }

            CueInEditorSettingsCard(title: "Timeline fill") {
                executionPoolGroupContent
            }

            CueInEditorSettingsCard(title: "List background") {
                canvasBackgroundGroupContent
            }
        }
    }

    private var executionPoolGroupContent: some View {
        Toggle(isOn: $pullsTasksFromExecutionPool) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Use execution pool for tasks")
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                Text("When off, Timeline fill blocks stay empty and do not claim tasks from your queued timeline pool.")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
            }
        }
        .tint(CueInColors.accentFocus)
        .padding(.horizontal, CueInSpacing.md)
        .padding(.vertical, CueInSpacing.sm)
        .background(CueInColors.surfaceSecondary.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
    }

    private var scheduleTimerGroupContent: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            Text("Style of the live countdown shown in schedule blocks.")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)

            VStack(spacing: 0) {
                ForEach(TodayDisplayPreferences.ScheduleBlockTimerStyle.allCases) { style in
                    choiceRow(
                        icon: style.icon,
                        title: style.title,
                        subtitle: style.subtitle,
                        isSelected: style == scheduleBlockTimerStyle
                    ) {
                        scheduleBlockTimerStyleRaw = style.rawValue
                    }
                }
            }

            Toggle(isOn: $scheduleBlockTimerShowsSeconds) {
                runningLineToggleLabel(
                    title: "Show seconds",
                    detail: "Applies to all timer styles and all schedule block designs."
                )
            }
            .tint(CueInColors.accentFocus)
            .padding(.horizontal, CueInSpacing.md)
            .padding(.vertical, CueInSpacing.sm)
            .background(CueInColors.surfaceSecondary.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
        }
    }

    // MARK: Schedule — block design

    private func blockDesignCell(_ d: TodayDisplayPreferences.ScheduleDesign) -> some View {
        let selected = d == design
        return Button {
            scheduleDesignRaw = d.rawValue
        } label: {
            VStack(alignment: .leading, spacing: CueInSpacing.xs) {
                Image(systemName: d.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected ? CueInColors.accentFocus : CueInColors.textPrimary)
                Text(d.title)
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(CueInSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                    .fill(CueInColors.surfaceSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                    .strokeBorder(
                        selected ? CueInColors.accentFocus.opacity(0.85) : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Schedule — day progress (running line)

    private var dayProgressGroupContent: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            Text("The bar and timer at the top while your day is running. The fill uses the accent colors from today’s block icons. Size and bar weight apply to every preset; use More options for display toggles.")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Preset")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: CueInSpacing.sm) {
                        ForEach(TodayDisplayPreferences.RunningLineStyle.allCases) { s in
                            runningLineStyleChip(s)
                        }
                    }
                }
            }

            Text(runningLine.subtitle)
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                Text("Fallback accent")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: CueInSpacing.md) {
                        ForEach(TodayDisplayPreferences.ActiveBlockEmphasis.allCases) { e in
                            accentSwatch(e)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                HStack {
                    Text("Size")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                    Spacer()
                }
                Picker("Size", selection: $runningLineSizeRaw) {
                    ForEach(TodayDisplayPreferences.RunningLineSize.allCases) { s in
                        Text(s.title).tag(s.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                HStack {
                    Text("Progress bar weight")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                    Spacer()
                }
                Picker("Bar weight", selection: $runningLineBarWeightRaw) {
                    ForEach(TodayDisplayPreferences.RunningLineBarWeight.allCases) { w in
                        Text(w.title).tag(w.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            DisclosureGroup(isExpanded: $showRunningLineAdvanced) {
                VStack(alignment: .leading, spacing: 0) {
                    Toggle(isOn: $runningLineFrostedCard) {
                        runningLineToggleLabel(
                            title: "Frosted card",
                            detail: "Soft glass or material behind the line (Minimal, Bar, Liquid, Orbit)."
                        )
                    }
                    .tint(CueInColors.accentFocus)
                    rowDivider
                    Toggle(isOn: $runningLineShowBlockTitle) {
                        runningLineToggleLabel(
                            title: "Show current block name",
                            detail: "Hides the title in styles that show it (not Minimal)."
                        )
                    }
                    .tint(CueInColors.accentFocus)
                    rowDivider
                    Toggle(isOn: $runningLineShowDayPercent) {
                        runningLineToggleLabel(
                            title: "Show day %",
                            detail: "Percent of the schedule day (Minimal, Orbit, Ticker)."
                        )
                    }
                    .tint(CueInColors.accentFocus)
                }
                .padding(.top, CueInSpacing.sm)
            } label: {
                HStack {
                    Text("More options")
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                    Spacer()
                }
            }
        }
    }

    private var pauseBehaviorGroupContent: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            Text("Choose what happens when a stopped schedule resumes.")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)

            VStack(spacing: 0) {
                ForEach(TodayDisplayPreferences.SchedulePauseBehavior.allCases) { behavior in
                    choiceRow(
                        icon: behavior.icon,
                        title: behavior.title,
                        subtitle: behavior.subtitle,
                        isSelected: behavior == schedulePauseBehavior
                    ) {
                        schedulePauseBehaviorRaw = behavior.rawValue
                    }
                }
            }
        }
    }

    private func runningLineStyleChip(_ s: TodayDisplayPreferences.RunningLineStyle) -> some View {
        let on = s == runningLine
        return Button {
            runningLineStyleRaw = s.rawValue
        } label: {
            HStack(spacing: 6) {
                Image(systemName: s.icon)
                    .font(.system(size: 14, weight: .semibold))
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.chipTitle)
                        .font(CueInTypography.captionMedium)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(on ? CueInColors.accentFocus.opacity(0.2) : CueInColors.surfaceSecondary)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        on ? CueInColors.accentFocus.opacity(0.9) : CueInColors.divider,
                        lineWidth: on ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func accentSwatch(_ e: TodayDisplayPreferences.ActiveBlockEmphasis) -> some View {
        let on = e == activeBlockEmphasis
        return Button {
            activeBlockEmphasisRaw = e.rawValue
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(e.swatchColor)
                        .frame(width: 32, height: 32)
                        .overlay {
                            Circle()
                                .strokeBorder(e == .monochrome ? Color.white.opacity(0.4) : Color.clear, lineWidth: 1)
                        }
                        .shadow(color: e.swatchColor.opacity(0.35), radius: on ? 4 : 0, x: 0, y: 0)
                    if on {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(e == .monochrome ? Color.black.opacity(0.55) : Color.white.opacity(0.95))
                    }
                }
                Text(e.shortName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CueInColors.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(e.title). \(e.subtitle)")
    }

    private func runningLineToggleLabel(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(CueInTypography.bodyMedium)
                .foregroundStyle(CueInColors.textPrimary)
            Text(detail)
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)
        }
        .padding(.vertical, CueInSpacing.xs)
    }

    // MARK: Schedule — list content + canvas

    private var blockFieldTogglesGroupContent: some View {
        VStack(spacing: 0) {
            toggleRow(title: "Start time", isOn: $showScheduleStartTime)
            rowDivider
            toggleRow(title: "Duration", isOn: $showScheduleDuration)
            rowDivider
            toggleRow(title: "Time range", isOn: $showScheduleTimeRange)
        }
        .padding(.horizontal, CueInSpacing.md)
        .padding(.vertical, CueInSpacing.xs)
        .background(CueInColors.surfaceSecondary.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
    }

    private var canvasBackgroundGroupContent: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            Text("Only behind the schedule scroll — not the rest of the app.")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)

            Toggle(isOn: $canvasDotsBackground) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Canvas dots")
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                    Text("Dotted grid. With Block style set to Liquid glass, blocks can use the real iOS 26 glass so the pattern shows through.")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textSecondary)
                }
            }
            .tint(CueInColors.accentFocus)
            .padding(.horizontal, CueInSpacing.md)
            .padding(.vertical, CueInSpacing.sm)
            .background(CueInColors.surfaceSecondary.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
        }
    }

    private var rowDivider: some View {
        Divider().overlay(CueInColors.divider)
    }

    private func sectionSubheader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(CueInTypography.caption)
            .foregroundStyle(CueInColors.textTertiary)
            .padding(.top, CueInSpacing.xs)
    }

    private func isScaleSelected(_ height: Double) -> Bool {
        abs(timelineHourHeight - height) < 0.5
    }

    private func choiceRow(
        icon: String,
        title: String,
        subtitle: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: CueInSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(CueInColors.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(CueInColors.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textSecondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? CueInColors.accentFocus : CueInColors.textTertiary.opacity(0.55))
            }
            .padding(.vertical, CueInSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(CueInTypography.bodyMedium)
                .foregroundStyle(CueInColors.textPrimary)
        }
        .tint(CueInColors.accentFocus)
        .padding(.vertical, CueInSpacing.sm)
    }

}

// MARK: - Settings discard (parent bindings)

private struct TodaySettingsBindingRollback: Equatable {
    let taskLedViewModeRaw: String
    let timelineLayoutModeRaw: String
    let timelineHourHeight: Double
    let scheduleDesignRaw: String
    let runningLineStyleRaw: String
    let activeBlockEmphasisRaw: String
    let runningLineSizeRaw: String
    let runningLineBarWeightRaw: String
    let runningLineFrostedCard: Bool
    let runningLineShowBlockTitle: Bool
    let runningLineShowDayPercent: Bool
    let schedulePauseBehaviorRaw: String
    let showScheduleStartTime: Bool
    let showScheduleDuration: Bool
    let showScheduleTimeRange: Bool
    let scheduleBlockTimerStyleRaw: String
    let scheduleBlockTimerShowsSeconds: Bool
    let pullsTasksFromExecutionPool: Bool
    let canvasDotsBackground: Bool
}

#Preview {
    ZStack {
        CueInColors.background.ignoresSafeArea()
        TodaySettingsSheet(
            isTaskLedMode: false,
            taskLedViewModeRaw: .constant(TodayDisplayPreferences.TaskLedViewMode.timeline.rawValue),
            timelineLayoutModeRaw: .constant("vertical"),
            timelineHourHeight: .constant(80),
            scheduleDesignRaw: .constant("glass"),
            runningLineStyleRaw: .constant(TodayDisplayPreferences.RunningLineStyle.minimal.rawValue),
            activeBlockEmphasisRaw: .constant(TodayDisplayPreferences.ActiveBlockEmphasis.brand.rawValue),
            runningLineSizeRaw: .constant(TodayDisplayPreferences.RunningLineSize.standard.rawValue),
            runningLineBarWeightRaw: .constant(TodayDisplayPreferences.RunningLineBarWeight.standard.rawValue),
            runningLineFrostedCard: .constant(true),
            runningLineShowBlockTitle: .constant(true),
            runningLineShowDayPercent: .constant(true),
            schedulePauseBehaviorRaw: .constant(TodayDisplayPreferences.SchedulePauseBehavior.preserveLength.rawValue),
            showScheduleStartTime: .constant(true),
            showScheduleDuration: .constant(false),
            showScheduleTimeRange: .constant(false),
            scheduleBlockTimerStyleRaw: .constant(TodayDisplayPreferences.ScheduleBlockTimerStyle.ring.rawValue),
            scheduleBlockTimerShowsSeconds: .constant(false),
            pullsTasksFromExecutionPool: .constant(true),
            canvasDotsBackground: .constant(false),
            onDismiss: {}
        )
    }
    .cueInPreferredColorScheme()
}
