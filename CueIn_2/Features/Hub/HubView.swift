import SwiftUI

// MARK: - Hub tool catalog
/// Single place to register Hub surfaces. Add a row here, then set `onSelect` (and optional sheet/navigation)
/// when that tool is ready — the grid picks up layout and styling automatically.

private struct HubToolDefinition: Identifiable {
    let id: String
    let systemImage: String
    let title: String
    let subtitle: String
    /// A live badge string (e.g. "Running", "Rain") shown when the tool has active state.
    var liveBadge: String? = nil
    /// When non-`nil`, the tile is tappable; otherwise it renders as a calm placeholder for upcoming work.
    var onSelect: (() -> Void)? = nil

    var isInteractive: Bool { onSelect != nil }

    /// ``AppTab`` destinations that already have a Hub catalog tile; avoid duplicating them in "Not in tab bar."
    static let appTabsCoveredByCatalog: Set<AppTab> = [.pomodoro, .sounds, .quantifiedSelf]

    /// Ordered list shown in the Hub grid — keep this the source of truth for "what lives in Hub."
    static let catalog: [HubToolDefinition] = [
        HubToolDefinition(id: "pomodoro",       systemImage: "timer",               title: "Timer",      subtitle: "Focus intervals"),
        HubToolDefinition(id: "sounds",         systemImage: "waveform",            title: "Sounds",     subtitle: "Focus audio"),
        HubToolDefinition(id: "quantifiedSelf", systemImage: "chart.xyaxis.line",   title: "Measures",   subtitle: "Quantified self"),
        HubToolDefinition(id: "library",        systemImage: "rectangle.stack.fill.badge.plus", title: "Library", subtitle: "Bookmarks & block library"),
        HubToolDefinition(id: "planning",       systemImage: "calendar",            title: "Planning",   subtitle: "Week & month view"),
        HubToolDefinition(id: "routines",       systemImage: "arrow.triangle.2.circlepath", title: "Routines", subtitle: "Repeatable systems"),
        HubToolDefinition(id: "schedules",      systemImage: "doc.text.fill",       title: "Schedules",  subtitle: "Day & week templates"),
        HubToolDefinition(id: "ai",             systemImage: "brain.head.profile",  title: "AI Tools",   subtitle: "Smart assistance"),
        HubToolDefinition(id: "integrations",   systemImage: "link",                title: "Integrations", subtitle: "Connect your stack"),
    ]
}

// MARK: - HubView
/// Hub tab — command center. Goals are the hero; tools radiate outward.

struct HubView: View {
    @AppStorage(AppTab.storageKey) private var storedTabsRaw = AppTab.storageValue(for: AppTab.defaultTabs)
    @AppStorage(TodayDisplayPreferences.taskLedViewMode) private var taskLedViewModeRaw
        = TodayDisplayPreferences.TaskLedViewMode.timeline.rawValue
    @State private var path: [GoalStrategyRoute] = []
    @State private var activeGoalSheet: GoalStrategySheet?
    @State private var showSettings = false
    @State private var showDevNotebook = false
    @State private var showQuantifiedSelfSheet = false
    @State private var showLibrarySheet = false
    @State private var librarySheetInitialSegment: LibraryHomeSegment = .tasks
    @Bindable private var todayViewModel = TodayViewModel.shared
    @Bindable private var goalStore = GoalStrategyStore.shared
    @Bindable private var tasksStore = TasksStore.shared
    @Bindable private var pomodoroStore = PomodoroStore.shared
    @Bindable private var focusSoundStore = FocusSoundscapeStore.shared

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HubGoalsHeroBlock(
                        goalStore: goalStore,
                        tasksStore: tasksStore,
                        onCreateGoal: { activeGoalSheet = .createGoal(templateID: nil) },
                        onOpenGoalsHome: {
                            path = [.home]
                        }
                    )
                    .padding(.top, CueInSpacing.base)
                    .padding(.bottom, CueInSpacing.xxl)

                    toolsSection
                        .padding(.bottom, CueInSpacing.xxl)

                    if !missingNavbarTabs.isEmpty {
                        offTabBarModulesSection
                            .padding(.bottom, CueInSpacing.xxl)
                    }

                    systemSection
                }
                .padding(.bottom, CueInLayout.scrollBottomInset)
            }
            .background(CueInColors.background)
            .navigationTitle("Hub")
            .cueInNavigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: CueInToolbarPlacement.topBarTrailing) {
                    Button {
                        showDevNotebook = true
                    } label: {
                        Image(systemName: "note.text")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(CueInColors.textPrimary)
                    }
                    .accessibilityLabel("Open Developer Notebook")

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(CueInColors.textPrimary)
                    }
                    .accessibilityLabel("Open Settings")
                }
            }
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
        .sheet(isPresented: $showQuantifiedSelfSheet) {
            QuantifiedSelfView(onRequestDismiss: { showQuantifiedSelfSheet = false })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(isPresented: $showLibrarySheet) {
            LibraryView(initialSegment: librarySheetInitialSegment) {
                showLibrarySheet = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
    }

    // MARK: - Navigation Destinations

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
                onPresentSheet: { activeGoalSheet = $0 },
                showsHubBackButton: true
            )

        case .goal(let id):
            GoalDetailView(
                goalID: id,
                store: goalStore,
                tasksStore: tasksStore,
                onPresentSheet: { activeGoalSheet = $0 },
                showsHubBackButton: true
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


        }
    }

    // MARK: - Tab bar shortcuts (modules not pinned in the navbar)

    /// Order matches navbar customization (`AppTab.editableTabs`) minus overflow/meta slots.
    private var missingNavbarTabs: [AppTab] {
        let visible = AppTab.storedTabs(from: storedTabsRaw)
        let order: [AppTab] = [.schedule, .taskLed, .tasks, .projects, .stats, .goals, .antiTodo, .quantifiedSelf, .pomodoro, .sounds]
        return order.filter { tab in
            !visible.contains(tab) && !HubToolDefinition.appTabsCoveredByCatalog.contains(tab)
        }
    }

    private var taskLedPresentation: TodayDisplayPreferences.TaskLedViewMode {
        TodayDisplayPreferences.TaskLedViewMode(rawValue: taskLedViewModeRaw) ?? .timeline
    }

    private var offTabBarModulesSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            sectionLabel("Not in tab bar")
                .padding(.horizontal, CueInSpacing.screenHorizontal)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: CueInSpacing.md),
                    GridItem(.flexible(), spacing: CueInSpacing.md),
                ],
                spacing: CueInSpacing.md
            ) {
                ForEach(missingNavbarTabs, id: \.self) { tab in
                    toolTile(jumpTileDefinition(for: tab))
                }
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)
        }
    }

    private func postSwitchToShellTab(_ tab: AppTab) {
        NotificationCenter.default.post(
            name: .cueInSwitchTab,
            object: nil,
            userInfo: [CueInShellNotification.switchTabUserInfoKey: tab.rawValue]
        )
    }

    private func jumpTileDefinition(for tab: AppTab) -> HubToolDefinition {
        let onSelect: () -> Void = { postSwitchToShellTab(tab) }
        switch tab {
        case .schedule:
            return HubToolDefinition(
                id: "jump-tab-\(tab.rawValue)",
                systemImage: tab.icon,
                title: tab.label,
                subtitle: "Formula-based day",
                onSelect: onSelect
            )
        case .taskLed:
            return HubToolDefinition(
                id: "jump-tab-\(tab.rawValue)",
                systemImage: taskLedPresentation.icon,
                title: tab.rearrangementPickerLabel,
                subtitle: "Task-led day",
                onSelect: onSelect
            )
        case .tasks:
            return HubToolDefinition(
                id: "jump-tab-\(tab.rawValue)",
                systemImage: tab.icon,
                title: tab.label,
                subtitle: "Fields, projects & tasks",
                onSelect: onSelect
            )
        case .projects:
            return HubToolDefinition(
                id: "jump-tab-\(tab.rawValue)",
                systemImage: tab.icon,
                title: tab.label,
                subtitle: "Project home",
                onSelect: onSelect
            )
        case .stats:
            return HubToolDefinition(
                id: "jump-tab-\(tab.rawValue)",
                systemImage: tab.icon,
                title: tab.label,
                subtitle: "Trends & daily snapshot",
                onSelect: onSelect
            )
        case .goals:
            return HubToolDefinition(
                id: "jump-tab-\(tab.rawValue)",
                systemImage: tab.icon,
                title: tab.label,
                subtitle: "Strategies & milestones",
                onSelect: onSelect
            )
        case .antiTodo:
            return HubToolDefinition(
                id: "jump-tab-\(tab.rawValue)",
                systemImage: tab.icon,
                title: tab.label,
                subtitle: "Track what you skip",
                onSelect: onSelect
            )
        case .quantifiedSelf:
            return HubToolDefinition(
                id: "jump-tab-\(tab.rawValue)",
                systemImage: tab.icon,
                title: tab.label,
                subtitle: "Trackers & logs",
                onSelect: onSelect
            )
        case .pomodoro:
            return HubToolDefinition(
                id: "jump-tab-\(tab.rawValue)",
                systemImage: tab.icon,
                title: tab.label,
                subtitle: "Focus intervals",
                onSelect: onSelect
            )
        case .sounds:
            return HubToolDefinition(
                id: "jump-tab-\(tab.rawValue)",
                systemImage: tab.icon,
                title: tab.label,
                subtitle: "Focus audio",
                onSelect: onSelect
            )
        case .hub, .more:
            return HubToolDefinition(
                id: "jump-tab-\(tab.rawValue)",
                systemImage: tab.icon,
                title: tab.label,
                subtitle: "",
                onSelect: nil
            )
        }
    }

    // MARK: - Tools Grid

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            sectionLabel("Tools")
                .padding(.horizontal, CueInSpacing.screenHorizontal)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: CueInSpacing.md),
                    GridItem(.flexible(), spacing: CueInSpacing.md),
                ],
                spacing: CueInSpacing.md
            ) {
                ForEach(resolvedToolCatalog) { tool in
                    toolTile(tool)
                }
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)
        }
    }

    @ViewBuilder
    private func toolTile(_ tool: HubToolDefinition) -> some View {
        let content = toolTileContent(tool)
        if let action = tool.onSelect {
            Button(action: action) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    @ViewBuilder
    private func toolTileContent(_ tool: HubToolDefinition) -> some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            // Icon row
            HStack {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(tool.isInteractive ? CueInColors.textPrimary : CueInColors.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(CueInColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: CueInSpacing.chipRadius, style: .continuous))

                Spacer()

                if let badge = tool.liveBadge {
                    liveBadgeDot(label: badge)
                } else if !tool.isInteractive {
                    Text("Soon")
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(CueInColors.activeHint, in: Capsule())
                }
            }

            // Text
            VStack(alignment: .leading, spacing: 3) {
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
        .padding(CueInSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CueInColors.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(CueInColors.cardBorder, lineWidth: 0.5)
        )
        .opacity(tool.isInteractive ? 1 : 0.45)
    }

    // MARK: - System Section

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            sectionLabel("Device")
                .padding(.horizontal, CueInSpacing.screenHorizontal)

            VStack(spacing: 0) {
                systemRow(
                    icon: "note.text.badge.plus",
                    title: "Dev Notebook",
                    action: { showDevNotebook = true }
                )

                Divider()
                    .background(CueInColors.divider)
                    .padding(.leading, CueInSpacing.screenHorizontal + 32 + CueInSpacing.md)

                systemRow(
                    icon: "gearshape",
                    title: "Settings",
                    action: { showSettings = true }
                )
            }
            .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                    .strokeBorder(CueInColors.cardBorder, lineWidth: 0.5)
            )
            .padding(.horizontal, CueInSpacing.screenHorizontal)
        }
    }

    private func systemRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: CueInSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CueInColors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(CueInColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: CueInSpacing.chipRadius - 2, style: .continuous))

                Text(title)
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CueInColors.textTertiary)
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)
            .frame(height: 52)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    /// Uppercase micro label for section headings.
    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(CueInTypography.micro)
            .foregroundStyle(CueInColors.textTertiary)
            .tracking(1.0)
    }

    /// Pulsing green dot with a short badge label — used for live tool states.
    private func liveBadgeDot(label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(CueInColors.accentFocus)
                .frame(width: 6, height: 6)
            Text(label)
                .font(CueInTypography.micro)
                .foregroundStyle(CueInColors.accentFocus)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(CueInColors.accentFocus.opacity(0.12), in: Capsule())
    }

    // MARK: - Resolved Catalog

    /// Live subtitles where a tile should reflect app state (e.g. future pins).
    private var resolvedToolCatalog: [HubToolDefinition] {
        HubToolDefinition.catalog.map { tool in
            switch tool.id {
            case "planning":
                return HubToolDefinition(
                    id: tool.id,
                    systemImage: tool.systemImage,
                    title: tool.title,
                    subtitle: planningTileSubtitle,
                    onSelect: tool.onSelect
                )
            case "quantifiedSelf":
                return HubToolDefinition(
                    id: tool.id,
                    systemImage: tool.systemImage,
                    title: tool.title,
                    subtitle: tool.subtitle,
                    onSelect: { showQuantifiedSelfSheet = true }
                )
            case "library":
                return HubToolDefinition(
                    id: tool.id,
                    systemImage: tool.systemImage,
                    title: tool.title,
                    subtitle: libraryTileSubtitle,
                    onSelect: {
                        librarySheetInitialSegment = .tasks
                        showLibrarySheet = true
                    }
                )
            case "pomodoro":
                return HubToolDefinition(
                    id: tool.id,
                    systemImage: tool.systemImage,
                    title: tool.title,
                    subtitle: pomodoroHubSubtitle,
                    liveBadge: pomodoroLiveBadge,
                    onSelect: {
                        NotificationCenter.default.post(name: .cueInOpenFocus, object: nil)
                    }
                )
            case "sounds":
                return HubToolDefinition(
                    id: tool.id,
                    systemImage: tool.systemImage,
                    title: tool.title,
                    subtitle: soundsHubSubtitle,
                    liveBadge: soundsLiveBadge,
                    onSelect: {
                        NotificationCenter.default.post(name: .cueInOpenSounds, object: nil)
                    }
                )
            default:
                return tool
            }
        }
    }

    private var libraryTileSubtitle: String {
        let t = tasksStore.tasks.filter(\.savesToArchive).count
        let s = FormulaLibraryService.customSchedules().count
        let b = FormulaLibraryService.customBlockPresets().count
        let total = t + s + b
        if total == 0 { return "Tasks tab & Blocks tab" }
        return "\(t) bookmarked · \(s) day layouts · \(b) block presets"
    }

    private var planningTileSubtitle: String {
        let count = todayViewModel.futurePinnedScheduleBlocks.count
        if count == 0 { return "Week & month view" }
        return "\(count) future pin\(count == 1 ? "" : "s")"
    }

    private var pomodoroHubSubtitle: String {
        if pomodoroStore.isRunning {
            let m = pomodoroStore.remainingSeconds / 60
            let s = pomodoroStore.remainingSeconds % 60
            return String(format: "%02d:%02d remaining", m, s)
        }
        if pomodoroStore.pausedRemainingSeconds != nil { return "Paused" }
        return "Focus intervals"
    }

    private var pomodoroLiveBadge: String? {
        guard pomodoroStore.isRunning else { return nil }
        return pomodoroStore.phase.title
    }

    private var soundsHubSubtitle: String {
        if focusSoundStore.isPlaying, focusSoundStore.preset != .off {
            return focusSoundStore.preset.title
        }
        return "Focus audio"
    }

    private var soundsLiveBadge: String? {
        guard focusSoundStore.isPlaying, focusSoundStore.preset != .off else { return nil }
        return "Playing"
    }
}

#Preview {
    ZStack {
        CueInColors.background.ignoresSafeArea()
        HubView()
    }
    .cueInPreferredColorScheme()
}
