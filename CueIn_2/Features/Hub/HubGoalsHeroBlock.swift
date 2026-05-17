import Observation
import SwiftUI

// MARK: - Hub Goals hero (Hub tab)

/// Goals summary card for ``HubView`` — layout and detail controlled via the header menu and ``HubGoalsBlockPreferences``.
struct HubGoalsHeroBlock: View {

    @Bindable var goalStore: GoalStrategyStore
    @Bindable var tasksStore: TasksStore

    let onCreateGoal: () -> Void
    let onOpenGoalsHome: () -> Void

    @AppStorage(HubGoalsBlockPreferences.Keys.focusMode) private var focusMode = false
    @AppStorage(HubGoalsBlockPreferences.Keys.density) private var densityRaw = HubGoalsBlockPreferences.Density.comfortable.rawValue
    @AppStorage(HubGoalsBlockPreferences.Keys.showSectionSubtitle) private var showSectionSubtitle = false
    @AppStorage(HubGoalsBlockPreferences.Keys.showActiveCount) private var showActiveCount = true
    @AppStorage(HubGoalsBlockPreferences.Keys.showGoalDescription) private var showGoalDescription = false
    @AppStorage(HubGoalsBlockPreferences.Keys.showSubgoalCounts) private var showSubgoalCounts = false
    @AppStorage(HubGoalsBlockPreferences.Keys.showProgressBar) private var showProgressBar = true
    @AppStorage(HubGoalsBlockPreferences.Keys.showProgressRing) private var showProgressRing = false
    @AppStorage(HubGoalsBlockPreferences.Keys.showPercentage) private var showPercentage = true
    @AppStorage(HubGoalsBlockPreferences.Keys.showNextAction) private var showNextAction = false
    @AppStorage(HubGoalsBlockPreferences.Keys.showStageTitle) private var showStageTitle = false
    @AppStorage(HubGoalsBlockPreferences.Keys.showDates) private var showDates = false
    @AppStorage(HubGoalsBlockPreferences.Keys.stagesVisualization) private var stagesVisualizationRaw = HubGoalsBlockPreferences.StagesVisualization.off.rawValue
    @AppStorage(HubGoalsBlockPreferences.Keys.cardStyle) private var cardStyleRaw = HubGoalsBlockPreferences.CardStyle.surface.rawValue
    @AppStorage(HubGoalsBlockPreferences.Keys.showAccentRail) private var showAccentRail = true

    private var density: HubGoalsBlockPreferences.Density {
        HubGoalsBlockPreferences.Density(rawValue: densityRaw) ?? .comfortable
    }

    private var stagesVisualization: HubGoalsBlockPreferences.StagesVisualization {
        HubGoalsBlockPreferences.StagesVisualization(rawValue: stagesVisualizationRaw) ?? .off
    }

    private var cardStyle: HubGoalsBlockPreferences.CardStyle {
        HubGoalsBlockPreferences.CardStyle(rawValue: cardStyleRaw) ?? .surface
    }

    private var contentPadding: CGFloat {
        density == .compact ? CueInSpacing.md : CueInSpacing.base
    }

    private var rowStackSpacing: CGFloat {
        density == .compact ? CueInSpacing.sm : CueInSpacing.md
    }

    private var ringSize: CGFloat {
        density == .compact ? 30 : 36
    }

    private var titleFont: Font {
        density == .compact ? CueInTypography.body : CueInTypography.bodyMedium
    }

    private var maxVisibleGoals: Int {
        density == .compact ? 2 : 3
    }

    var body: some View {
        Group {
            switch cardStyle {
            case .surface:
                cardContent
                    .background(CueInColors.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                            .strokeBorder(CueInColors.cardBorder, lineWidth: 0.5)
                    )
            case .glass:
                cardContent
                    .glassSurface(cornerRadius: CueInSpacing.cardRadius)
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showAccentRail {
                Rectangle()
                    .fill(CueInColors.accentFocus)
                    .frame(height: 2)
            }

            VStack(alignment: .leading, spacing: rowStackSpacing) {
                headerRow

                if !focusMode {
                    if goalStore.activeGoals.isEmpty {
                        goalsEmptyState
                    } else {
                        VStack(spacing: rowStackSpacing) {
                            ForEach(goalStore.activeGoals.prefix(maxVisibleGoals)) { goal in
                                NavigationLink(value: GoalStrategyRoute.goal(goal.id)) {
                                    goalRow(goal)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(contentPadding)
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .center, spacing: CueInSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                sectionLabel("Goals")
                if showSectionSubtitle {
                    Text("In progress")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                }
            }

            Spacer(minLength: 0)

            if showActiveCount, !goalStore.activeGoals.isEmpty {
                NavigationLink(value: GoalStrategyRoute.home) {
                    Text("\(goalStore.activeGoals.count)")
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(CueInColors.surfaceTertiary, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open goals, \(goalStore.activeGoals.count) active")
            }

            goalsOptionsMenu
        }
    }

    private var goalsOptionsMenu: some View {
        Menu {
            Section {
                Button("Add goal", action: onCreateGoal)
                if !goalStore.activeGoals.isEmpty {
                    Button("Open goals list", action: onOpenGoalsHome)
                }
            }

            Section("Layout") {
                Toggle("Focus mode", isOn: $focusMode)
                Picker("Density", selection: $densityRaw) {
                    Text(HubGoalsBlockPreferences.Density.compact.menuTitle).tag(HubGoalsBlockPreferences.Density.compact.rawValue)
                    Text(HubGoalsBlockPreferences.Density.comfortable.menuTitle).tag(HubGoalsBlockPreferences.Density.comfortable.rawValue)
                }
            }

            Section("Header") {
                Toggle("Section subtitle", isOn: $showSectionSubtitle)
                Toggle("Active count", isOn: $showActiveCount)
                Toggle("Top accent rail", isOn: $showAccentRail)
            }

            Section("Rows") {
                Toggle("Goal description", isOn: $showGoalDescription)
                Toggle("Subgoal counts", isOn: $showSubgoalCounts)
                Toggle("Next action line", isOn: $showNextAction)
                Toggle("Current stage title", isOn: $showStageTitle)
                Toggle("Target dates", isOn: $showDates)
            }

            Section("Progress") {
                Toggle("Progress bar", isOn: $showProgressBar)
                Toggle("Progress ring", isOn: $showProgressRing)
                Toggle("Percentage", isOn: $showPercentage)
            }

            Section("Stages") {
                Picker("Stages view", selection: $stagesVisualizationRaw) {
                    ForEach(HubGoalsBlockPreferences.StagesVisualization.allCases) { mode in
                        Text(mode.menuTitle).tag(mode.rawValue)
                    }
                }
            }

            Section("Appearance") {
                Picker("Card style", selection: $cardStyleRaw) {
                    ForEach(HubGoalsBlockPreferences.CardStyle.allCases) { style in
                        Text(style.menuTitle).tag(style.rawValue)
                    }
                }
            }

            Section {
                Button("Reset to defaults") {
                    HubGoalsBlockPreferences.resetToDefaults()
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CueInColors.textSecondary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .menuActionDismissBehavior(.automatic)
        .accessibilityLabel("Goals block options")
    }

    // MARK: - Empty

    private var goalsEmptyState: some View {
        Button(action: onCreateGoal) {
            HStack(spacing: CueInSpacing.md) {
                Image(systemName: "target")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CueInColors.accentFocus)
                    .frame(width: 34, height: 34)
                    .background(CueInColors.accentFocus.opacity(0.12), in: RoundedRectangle(cornerRadius: CueInSpacing.chipRadius, style: .continuous))

                Text("Add goal")
                    .font(titleFont)
                    .foregroundStyle(CueInColors.textPrimary)

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(CueInColors.accentFocus.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Goal row

    @ViewBuilder
    private func goalRow(_ goal: Goal) -> some View {
        let progress = goalStore.progress(goal: goal, tasksStore: tasksStore)
        let summary = goalStore.progressSummary(goal: goal, tasksStore: tasksStore)

        VStack(alignment: .leading, spacing: density == .compact ? 4 : CueInSpacing.sm) {
            HStack(alignment: .center, spacing: CueInSpacing.md) {
                if showProgressRing {
                    HubGoalsProgressRing(progress: progress, size: ringSize)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(titleFont)
                        .foregroundStyle(CueInColors.textPrimary)
                        .lineLimit(1)

                    if showGoalDescription, !goal.description.isEmpty {
                        Text(goal.description)
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textTertiary)
                            .lineLimit(1)
                    }

                    if showStageTitle, let stage = goalStore.currentStage(for: goal) {
                        Text(stage.title)
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textSecondary)
                            .lineLimit(1)
                    }

                    if showSubgoalCounts, summary.total > 0 {
                        Text("\(summary.completed)/\(summary.total) subgoals")
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textTertiary)
                            .monospacedDigit()
                    }

                    if showNextAction, let line = nextActionLine(goal: goal) {
                        Text(line)
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textTertiary)
                            .lineLimit(2)
                    }

                    if showDates, let dateLine = goalDateLine(goal: goal) {
                        Text(dateLine)
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if showPercentage {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: density == .compact ? 12 : 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(CueInColors.textSecondary)
                }
            }

            if showProgressBar {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(CueInColors.surfaceTertiary)
                        Capsule()
                            .fill(CueInColors.accentFocus)
                            .frame(width: max(0, geo.size.width * progress))
                    }
                }
                .frame(height: density == .compact ? 2 : 3)
            }

            stagesAttachment(for: goal)
        }
    }

    @ViewBuilder
    private func stagesAttachment(for goal: Goal) -> some View {
        let stages = goal.stages.filter { $0.status != .skipped }
        switch stagesVisualization {
        case .off:
            EmptyView()
        case .minimalBar:
            if !stages.isEmpty {
                HubGoalsStagesMinimalBar(stages: stages)
            }
        case .expandedList:
            if !stages.isEmpty {
                HubGoalsStagesExpandedList(stages: Array(stages.prefix(6)))
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(CueInTypography.micro)
            .foregroundStyle(CueInColors.textTertiary)
            .tracking(1.0)
    }

    private func nextActionLine(goal: Goal) -> String? {
        guard let stage = goalStore.currentStage(for: goal) else { return nil }
        let open = stage.subgoals.filter { $0.status != .completed && $0.status != .skipped }
        guard let sub = open.first(where: { $0.status == .active }) ?? open.first(where: { $0.status == .open }) else {
            return nil
        }
        return sub.title
    }

    private func goalDateLine(goal: Goal) -> String? {
        var parts: [String] = []
        if let d = goal.targetDate {
            parts.append("Goal \(Self.shortDate.string(from: d))")
        }
        if let stage = goalStore.currentStage(for: goal), let d = stage.targetDate {
            parts.append("Stage \(Self.shortDate.string(from: d))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}

// MARK: - Progress ring

private struct HubGoalsProgressRing: View {
    let progress: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(CueInColors.surfaceTertiary, lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(CueInColors.accentFocus, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Stages visuals

private struct HubGoalsStagesMinimalBar: View {
    let stages: [GoalStage]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(stages) { stage in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(stageStatusColor(stage.status))
                    .frame(width: 5, height: 10)
                    .opacity(stage.status == .completed ? 0.45 : 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stages")
    }

    private func stageStatusColor(_ status: GoalStageStatus) -> Color {
        switch status {
        case .planned: return CueInColors.textTertiary
        case .active: return CueInColors.accentFocus
        case .paused: return CueInColors.textSecondary
        case .completed: return CueInColors.accentFocus.opacity(0.35)
        case .skipped: return CueInColors.surfaceTertiary
        }
    }
}

private struct HubGoalsStagesExpandedList: View {
    let stages: [GoalStage]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(stages) { stage in
                HStack(spacing: 6) {
                    Circle()
                        .fill(stageDotColor(stage.status))
                        .frame(width: 5, height: 5)
                    Text(stage.title)
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(stage.status.label)
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                }
            }
        }
        .padding(.top, 2)
    }

    private func stageDotColor(_ status: GoalStageStatus) -> Color {
        switch status {
        case .planned: return CueInColors.textTertiary
        case .active: return CueInColors.accentFocus
        case .paused: return CueInColors.textSecondary
        case .completed: return CueInColors.accentFocus.opacity(0.5)
        case .skipped: return CueInColors.surfaceTertiary
        }
    }
}
