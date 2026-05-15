import SwiftUI

// MARK: - Hub tool catalog
/// Single place to register Hub surfaces. Add a row here, then set `onSelect` (and optional sheet/navigation)
/// when that tool is ready — the grid picks up layout and styling automatically.

private struct HubToolDefinition: Identifiable {
    let id: String
    let systemImage: String
    let title: String
    let subtitle: String
    /// When non-`nil`, the tile is tappable; otherwise it renders as a calm placeholder for upcoming work.
    var onSelect: (() -> Void)? = nil

    var isInteractive: Bool { onSelect != nil }

    /// Ordered list shown in the Hub grid — keep this the source of truth for “what lives in Hub.”
    static let catalog: [HubToolDefinition] = [
        HubToolDefinition(id: "goals", systemImage: "target", title: "Goals", subtitle: "Direction & milestones"),
        HubToolDefinition(id: "schedules", systemImage: "doc.text.fill", title: "Schedules", subtitle: "Day & week templates"),
        HubToolDefinition(id: "routines", systemImage: "arrow.triangle.2.circlepath", title: "Routines", subtitle: "Repeatable systems"),
        HubToolDefinition(id: "ai", systemImage: "brain.head.profile", title: "AI Tools", subtitle: "Smart assistance"),
        HubToolDefinition(id: "integrations", systemImage: "link", title: "Integrations", subtitle: "Connect your stack"),
        HubToolDefinition(id: "planning", systemImage: "calendar", title: "Planning", subtitle: "Week & month view"),
    ]
}

// MARK: - HubView
/// Hub tab — system-building home. Layout is driven by `HubToolDefinition.catalog` for easy expansion.

struct HubView: View {
    @State private var path: [GoalStrategyRoute] = []
    @State private var activeGoalSheet: GoalStrategySheet?
    @State private var showSettings = false
    @State private var showDevNotebook = false
    @Bindable private var todayViewModel = TodayViewModel.shared
    @Bindable private var goalStore = GoalStrategyStore.shared
    @Bindable private var tasksStore = TasksStore.shared

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: CueInSpacing.xxl) {
                    headerBlock

                    toolsSection

                    planningSection

                    goalsSection

                    systemSection
                }
                .padding(.bottom, CueInLayout.scrollBottomInset)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: GoalStrategyRoute.self, destination: goalDestination)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cueInShowCreateGoal)) { _ in
            if path.last != .home {
                path.append(.home)
            }
            activeGoalSheet = .createGoal(templateID: nil)
        }
        .sheet(item: $activeGoalSheet, content: goalSheetContent)
        .sheet(isPresented: $showDevNotebook) {
            NavigationStack {
                DevNotebookView()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .onChange(of: showDevNotebook) { _, isPresented in
            DevNotebookContext.shared.hubNotebookSheetPresented = isPresented
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                DataAndResetSettingsView()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
    }

    @ViewBuilder
    private func goalDestination(_ route: GoalStrategyRoute) -> some View {
        switch route {
        case .home:
            GoalsHomeView(
                store: goalStore,
                tasksStore: tasksStore,
                onCreateGoal: { template in
                    activeGoalSheet = .createGoal(templateID: template?.id)
                },
                onPresentSheet: { activeGoalSheet = $0 }
            )

        case .goal(let id):
            GoalDetailView(
                goalID: id,
                store: goalStore,
                tasksStore: tasksStore,
                onPresentSheet: { activeGoalSheet = $0 }
            )
        }
    }

    @ViewBuilder
    private func goalSheetContent(_ sheet: GoalStrategySheet) -> some View {
        switch sheet {
        case .createGoal, .editGoal:
            GoalEditorSheet(
                sheet: sheet,
                store: goalStore,
                onCreated: { id in path.append(.goal(id)) },
                onDismiss: { activeGoalSheet = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)

        case .createStage, .editStage:
            GoalStageEditorSheet(
                sheet: sheet,
                store: goalStore,
                onDismiss: { activeGoalSheet = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)

        case .createSubgoal, .editSubgoal:
            GoalSubgoalEditorSheet(
                sheet: sheet,
                store: goalStore,
                onDismiss: { activeGoalSheet = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)

        case .linkWork(let goalID, let stageID, let subgoalID):
            GoalWorkLinkPickerSheet(
                goalID: goalID,
                stageID: stageID,
                subgoalID: subgoalID,
                store: goalStore,
                tasksStore: tasksStore,
                onDismiss: { activeGoalSheet = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)

        case .review(let goalID):
            GoalReviewEntrySheet(
                goalID: goalID,
                store: goalStore,
                onDismiss: { activeGoalSheet = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
    }

    // MARK: - Sections

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.lg) {
            VStack(alignment: .leading, spacing: CueInSpacing.xs) {
                Text("Hub")
                    .font(CueInTypography.largeTitle)
                    .foregroundStyle(CueInColors.textPrimary)

                Text("Shape the system behind Today — goals, structure, and tools in one calm place.")
                    .font(CueInTypography.body)
                    .foregroundStyle(CueInColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 0) {
                hubMetric(title: "Tools", value: "\(resolvedToolCatalog.count)")
                verticalRule
                hubMetric(title: "Goals", value: "\(goalStore.activeGoals.count)")
                verticalRule
                hubMetric(title: "Pinned ahead", value: futurePinsLabel)
            }
            .padding(.vertical, CueInSpacing.md)
            .padding(.horizontal, CueInSpacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                    .strokeBorder(CueInColors.cardBorder, lineWidth: 0.5)
            )
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.top, CueInSpacing.base)
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            sectionHeading("Tools & modules", caption: nil)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: CueInSpacing.md),
                    GridItem(.flexible(), spacing: CueInSpacing.md),
                ],
                spacing: CueInSpacing.md
            ) {
                ForEach(resolvedToolCatalog) { tool in
                    hubToolTile(tool)
                }
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            sectionHeading("Active goals", caption: goalStore.activeGoals.isEmpty ? "Ready" : "\(goalStore.activeGoals.count)")

            if goalStore.activeGoals.isEmpty {
                Button {
                    activeGoalSheet = .createGoal(templateID: nil)
                } label: {
                    CueInCard(padding: CueInSpacing.md) {
                        HStack(spacing: CueInSpacing.md) {
                            Image(systemName: "target")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(CueInColors.accentFocus)
                                .frame(width: 40, height: 40)
                                .background(CueInColors.accentFocus.opacity(0.14), in: RoundedRectangle(cornerRadius: CueInSpacing.chipRadius, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Create your first grand goal")
                                    .font(CueInTypography.bodyMedium)
                                    .foregroundStyle(CueInColors.textPrimary)
                                Text("Stages and links can come later.")
                                    .font(CueInTypography.caption)
                                    .foregroundStyle(CueInColors.textTertiary)
                            }

                            Spacer()

                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CueInColors.textTertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: CueInSpacing.sm) {
                    ForEach(goalStore.activeGoals.prefix(3)) { goal in
                        NavigationLink(value: GoalStrategyRoute.goal(goal.id)) {
                            hubGoalPreviewRow(goal)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            sectionHeading("On this device", caption: nil)

            VStack(spacing: CueInSpacing.sm) {
                navigationRowCard(
                    icon: "note.text.badge.plus",
                    title: "Dev notebook",
                    subtitle: "Ideas, bugs, and design notes",
                    action: { showDevNotebook = true }
                )

                navigationRowCard(
                    icon: "gearshape.fill",
                    title: "Settings",
                    subtitle: "Preferences, account, and data",
                    action: { showSettings = true }
                )
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    // MARK: - Planning (unchanged data, clearer framing)

    private var planningSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            sectionHeading("Planning snapshot", caption: planningSubtitle)

            if todayViewModel.futurePinnedScheduleBlocks.isEmpty {
                CueInCard(padding: CueInSpacing.md) {
                    HStack(spacing: CueInSpacing.md) {
                        Image(systemName: "calendar")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CueInColors.textTertiary)
                            .frame(width: 40, height: 40)
                            .background(CueInColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: CueInSpacing.chipRadius, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("No future pinned blocks")
                                .font(CueInTypography.bodyMedium)
                                .foregroundStyle(CueInColors.textPrimary)
                            Text("Pinned blocks scheduled after today will appear here.")
                                .font(CueInTypography.caption)
                                .foregroundStyle(CueInColors.textTertiary)
                        }
                    }
                }
            } else {
                VStack(spacing: CueInSpacing.sm) {
                    ForEach(todayViewModel.futurePinnedScheduleBlocks.prefix(6)) { block in
                        futurePinnedBlockRow(block)
                    }
                }
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    // MARK: - Components

    /// Live subtitles where a tile should reflect app state (e.g. future pins).
    private var resolvedToolCatalog: [HubToolDefinition] {
        HubToolDefinition.catalog.map { tool in
            switch tool.id {
            case "goals":
                return HubToolDefinition(
                    id: tool.id,
                    systemImage: tool.systemImage,
                    title: tool.title,
                    subtitle: goalsTileSubtitle,
                    onSelect: { path.append(.home) }
                )
            case "planning":
                return HubToolDefinition(
                    id: tool.id,
                    systemImage: tool.systemImage,
                    title: tool.title,
                    subtitle: planningTileSubtitle,
                    onSelect: tool.onSelect
                )
            default:
                return tool
            }
        }
    }

    private var goalsTileSubtitle: String {
        let active = goalStore.activeGoals.count
        if active == 0 { return "Direction & milestones" }
        let stalled = goalStore.activeGoals.reduce(0) {
            $0 + goalStore.staleSubgoals(for: $1, tasksStore: tasksStore).count
        }
        if stalled > 0 { return "\(active) active · \(stalled) stalled" }
        return "\(active) active roadmap\(active == 1 ? "" : "s")"
    }

    private var planningTileSubtitle: String {
        let count = todayViewModel.futurePinnedScheduleBlocks.count
        if count == 0 { return "Week & month view" }
        return "\(count) future pin\(count == 1 ? "" : "s")"
    }

    private var futurePinsLabel: String {
        let n = todayViewModel.futurePinnedScheduleBlocks.count
        if n == 0 { return "—" }
        return "\(n)"
    }

    private var planningSubtitle: String {
        let count = todayViewModel.futurePinnedScheduleBlocks.count
        if count == 0 { return "Nothing pinned ahead" }
        return "\(count) future pin\(count == 1 ? "" : "s")"
    }

    private func sectionHeading(_ title: String, caption: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(CueInTypography.title)
                .foregroundStyle(CueInColors.textPrimary)
            Spacer()
            if let caption {
                Text(caption)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func hubMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: CueInSpacing.xs) {
            Text(title.uppercased())
                .font(CueInTypography.micro)
                .foregroundStyle(CueInColors.textTertiary)
                .tracking(0.6)
            Text(value)
                .font(CueInTypography.headline)
                .foregroundStyle(CueInColors.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var verticalRule: some View {
        Rectangle()
            .fill(CueInColors.divider)
            .frame(width: 1, height: 36)
            .padding(.horizontal, CueInSpacing.base)
    }

    @ViewBuilder
    private func hubToolTile(_ tool: HubToolDefinition) -> some View {
        let tile = hubToolTileContent(tool)

        if let action = tool.onSelect {
            Button(action: action) { tile }
                .buttonStyle(.plain)
        } else {
            tile
        }
    }

    @ViewBuilder
    private func hubToolTileContent(_ tool: HubToolDefinition) -> some View {
        CueInCard {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: CueInSpacing.md) {
                    Image(systemName: tool.systemImage)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(tool.isInteractive ? CueInColors.textPrimary : CueInColors.textSecondary)
                        .frame(width: 40, height: 40)
                        .background(CueInColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: CueInSpacing.chipRadius, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(tool.title)
                            .font(CueInTypography.bodyMedium)
                            .foregroundStyle(CueInColors.textPrimary)

                        Text(tool.subtitle)
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textTertiary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(tool.isInteractive ? 1 : 0.92)

                if !tool.isInteractive {
                    Text("Soon")
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(CueInColors.activeHint, in: Capsule())
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if tool.isInteractive {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CueInColors.textTertiary)
                    .padding(12)
            }
        }
    }

    @ViewBuilder
    private func navigationRowCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CueInCard {
                HStack(spacing: CueInSpacing.md) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CueInColors.textSecondary)
                        .frame(width: 40, height: 40)
                        .background(CueInColors.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.chipRadius, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(CueInTypography.bodyMedium)
                            .foregroundStyle(CueInColors.textPrimary)
                        Text(subtitle)
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textTertiary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CueInColors.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func futurePinnedBlockRow(_ block: DayBlock) -> some View {
        CueInCard(padding: CueInSpacing.md) {
            HStack(spacing: CueInSpacing.md) {
                Image(systemName: block.resolvedTimelineGlyph)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CueInColors.resolvedTimelineAccent(blockType: block.type, hex: block.timelineAccentHex))
                    .frame(width: 40, height: 40)
                    .background(CueInColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: CueInSpacing.chipRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(block.title)
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                        .lineLimit(1)

                    Text(Self.futurePinnedDateLabel(block.startTime))
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                        .monospacedDigit()
                }

                Spacer()

                Image(systemName: "pin.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CueInColors.accentFixed)
            }
        }
    }

    @ViewBuilder
    private func hubGoalPreviewRow(_ goal: Goal) -> some View {
        let progress = goalStore.progress(goal: goal, tasksStore: tasksStore)
        let move = goalStore.nextMove(for: goal, tasksStore: tasksStore)
        CueInCard(padding: CueInSpacing.md) {
            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                HStack {
                    Image(systemName: goal.resolvedIconSystemName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(goal.color)
                        .frame(width: 30, height: 30)
                        .background(goal.color.opacity(0.14), in: RoundedRectangle(cornerRadius: CueInSpacing.chipRadius, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.title)
                            .font(CueInTypography.bodyMedium)
                            .foregroundStyle(CueInColors.textPrimary)
                            .lineLimit(1)
                        Text(move.title)
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text("\(Int(progress * 100))%")
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textSecondary)
                        .monospacedDigit()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(CueInColors.surfaceTertiary)
                        Capsule()
                            .fill(goal.color)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private static func futurePinnedDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d HH:mm")
        return formatter.string(from: date)
    }
}

#Preview {
    ZStack {
        CueInColors.background.ignoresSafeArea()
        HubView()
    }
    .preferredColorScheme(.dark)
}
