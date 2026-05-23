import SwiftUI

#if os(iOS)

// MARK: - AppShellView
/// Root container with content flowing under a floating bottom control cluster.

struct AppShellView: View {
    private enum ShellFabMotion {
        static let spring = Animation.spring(response: 0.36, dampingFraction: 0.86)
    }

    private enum AuxiliaryTaskSheet: String, Identifiable {
        case createProject
        case createField
        var id: String { rawValue }
    }

    @AppStorage(DayEngineMode.storageKey) private var todayModeRawValue = DayEngineMode.taskLed.rawValue
    @AppStorage(TodayDisplayPreferences.taskLedViewMode) private var taskLedViewModeRaw
        = TodayDisplayPreferences.TaskLedViewMode.timeline.rawValue
    @AppStorage(AppTab.storageKey) private var storedTabsRaw = AppTab.storageValue(for: AppTab.defaultTabs)
    @AppStorage(AppTab.selectedStorageKey) private var storedSelectedTabRaw = AppTab.taskLed.rawValue
    @State private var selectedTab: AppTab = .taskLed
    @State private var showShellQuickCapture = false
    @State private var showAntiTodoCapture = false
    @State private var fabOverflowPresented = false
    @State private var showFabBlockLibrary = false
    @State private var showHubOverflowSheet = false
    @State private var showStatsOverflowSheet = false
    @State private var auxiliaryTaskSheet: AuxiliaryTaskSheet?
    @State private var quickCaptureEditorDraft: TaskItem?
    @State private var quickCaptureExpanded = false
    @State private var quickCaptureFields: [Field] = []
    @State private var quickCaptureProjects: [Project] = []
    @State private var showExecutionSheet = false
    @State private var quickBlockNowMenuPresented = false
    @State private var quickBlockNowTitle = ""
    @State private var showTimelineCapture = false
    @State private var screenSafeAreaBottom: CGFloat = 0
    @State private var showDevCaptureSheet = false
    /// Tracks Timer / Sounds tab switches initiated from Hub tiles so a leading back control can return to Hub.
    @State private var auxiliaryTabOpenedFromHub: AppTab? = nil
    @AppStorage("cuein.devNotebook.showCaptureButton") private var showDevNotebookCaptureButton = false
    @AppStorage(TodayDisplayPreferences.pullsTasksFromExecutionPool) private var pullsTasksFromExecutionPool = true
    @AppStorage(TodayDisplayPreferences.scheduleShowsPagePlaybackControl) private var scheduleShowsPagePlaybackControl = false
    @Bindable private var toastCenter = CueInToastCenter.shared
    @State private var tasksStore = TasksStore.shared
    @State private var todayViewModel = TodayViewModel.shared
    @Bindable private var devNotebookContext = DevNotebookContext.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            CueInColors.background.ignoresSafeArea()
            // Read safe area once so the bar can adapt to home-button vs notched phones.
            GeometryReader { geo in
                Color.clear.preference(
                    key: BottomSafeAreaKey.self,
                    value: geo.safeAreaInsets.bottom
                )
            }
            .allowsHitTesting(false)
            .onPreferenceChange(BottomSafeAreaKey.self) { screenSafeAreaBottom = $0 }
            tabContent
            if fabOverflowPresented || quickBlockNowMenuPresented {
                Color.black.opacity(0.36)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissFloatingMenus()
                    }
                    .transition(.opacity)
            }
            if !quickCaptureComposerIsPresented {
                bottomFeedbackAndBar
                devNotebookFloatingControl
            }
            quickCaptureComposerOverlay
        }
        .onAppear {
            selectedTab = launchSelectedTab
            applyNavigationSideEffects(for: selectedTab)
            DevNotebookContext.shared.selectedTab = selectedTab
        }
        .task {
            await SupabaseAuthStore.shared.validateStoredSession()
        }
        .onChange(of: selectedTab) { _, newValue in
            storedSelectedTabRaw = newValue.rawValue
            if fabOverflowPresented { fabOverflowPresented = false }
            if quickBlockNowMenuPresented { quickBlockNowMenuPresented = false }
            if newValue != .tasks {
                tasksStore.clearCompleteUndo()
            }
            if newValue == .hub {
                auxiliaryTabOpenedFromHub = nil
            } else if newValue != .pomodoro && newValue != .sounds {
                auxiliaryTabOpenedFromHub = nil
            }
            applyNavigationSideEffects(for: newValue)
            DevNotebookContext.shared.selectedTab = newValue
            DevNotebookContext.shared.screenLabel = nil
        }
        .onChange(of: visibleTabs) { _, tabs in
            guard !tabs.contains(selectedTab) else { return }
            selectedTab = tabs.first ?? .hub
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                PomodoroStore.shared.refreshFromWallClockIfNeeded()
                Task { await SupabaseAuthStore.shared.validateStoredSession() }
            }
        }
        .sheet(isPresented: $showAntiTodoCapture) {
            AntiTodoCaptureSheet(store: .shared, onDismiss: { showAntiTodoCapture = false })
                .presentationDetents([.medium])
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showExecutionSheet) {
            ExecutionActionSheet(onDismiss: { showExecutionSheet = false })
                .presentationDetents([.medium])
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showFabBlockLibrary) {
            BlockTemplateLibrarySheet(
                onPick: { template in
                    todayViewModel.insertFormulaBlock(from: template)
                    showFabBlockLibrary = false
                },
                onDismiss: { showFabBlockLibrary = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(isPresented: $showHubOverflowSheet) {
            hubOverflowCreateSheet
                .presentationDetents([.medium])
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showStatsOverflowSheet) {
            statsOverflowPlaceholderSheet
                .presentationDetents([.medium])
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $auxiliaryTaskSheet) { sheet in
            switch sheet {
            case .createProject:
                CreateProjectSheet(mode: .create(fieldID: nil), store: .shared) {
                    auxiliaryTaskSheet = nil
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
            case .createField:
                CreateFieldSheet(mode: .create, store: .shared) {
                    auxiliaryTaskSheet = nil
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
            }
        }
        .sheet(item: $quickCaptureEditorDraft) { draft in
            TaskDetailSheet(
                mode: .create,
                store: .shared,
                configureCreateDraft: { item in
                    item = draft
                },
                onDismiss: { quickCaptureEditorDraft = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(isPresented: $showDevCaptureSheet) {
            DevNotebookCaptureSheet(isPresented: $showDevCaptureSheet, defaultKind: .moduleIdea) { kind, aiModel, body in
                let snap = DevNotebookContext.shared.makeSnapshot()
                DevNotebookStore.shared.add(DevNotebookEntry(
                    kind: kind,
                    aiModel: aiModel,
                    body: body,
                    moduleLabel: snap.moduleLabel,
                    contextLine: snap.contextLine
                ))
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cueInOpenFocus)) { _ in
            auxiliaryTabOpenedFromHub = .pomodoro
            selectedTab = .pomodoro
        }
        .onReceive(NotificationCenter.default.publisher(for: .cueInOpenSounds)) { _ in
            auxiliaryTabOpenedFromHub = .sounds
            selectedTab = .sounds
        }
        .onReceive(NotificationCenter.default.publisher(for: .cueInOpenBlockTemplateLibrary)) { _ in
            showFabBlockLibrary = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .cueInSwitchTab)) { note in
            guard let raw = note.userInfo?[CueInShellNotification.switchTabUserInfoKey] as? String,
                  let tab = AppTab(rawValue: raw)
            else { return }
            switch tab {
            case .pomodoro:
                auxiliaryTabOpenedFromHub = .pomodoro
            case .sounds:
                auxiliaryTabOpenedFromHub = .sounds
            default:
                break
            }
            selectedTab = tab
        }
    }

    private func openQuickCaptureEditor(_ draft: TaskItem) {
        dismissQuickCaptureComposer()
        deferPresentation {
            quickCaptureEditorDraft = draft
        }
    }

    @ViewBuilder
    private var quickCaptureComposerOverlay: some View {
        if quickCaptureComposerIsPresented {
            ZStack(alignment: .bottom) {
                (quickCaptureExpanded ? Color.black.opacity(0.10) : Color.clear)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissQuickCaptureComposer()
                    }

                VStack(spacing: 0) {
                    quickCaptureComposerHandle
                    QuickCaptureSheet(
                        store: .shared,
                        fields: quickCaptureFields,
                        projects: quickCaptureProjects,
                        onDismiss: dismissQuickCaptureComposer,
                        onExpand: openQuickCaptureEditor,
                        showsDragHandle: false,
                        presentationMode: quickCaptureExpanded ? .full : .compactComposer
                    )
                }
                .background(CueInColors.surfacePrimary)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: CueInSheetPresentation.cornerRadius,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: CueInSheetPresentation.cornerRadius,
                        style: .continuous
                    )
                )
                .frame(maxWidth: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .gesture(quickCaptureComposerDrag)
            }
            .zIndex(20)
        }
    }

    private var quickCaptureComposerHandle: some View {
        Capsule()
            .fill(CueInColors.textTertiary.opacity(0.42))
            .frame(width: 42, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(quickCaptureComposerAnimation) {
                    quickCaptureExpanded.toggle()
                }
            }
            .accessibilityLabel(quickCaptureExpanded ? "Collapse task composer" : "Expand task composer")
    }

    private var quickCaptureComposerDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onEnded { value in
                let vertical = value.translation.height
                let predicted = value.predictedEndTranslation.height
                let drag = abs(predicted) > abs(vertical) ? predicted : vertical

                withAnimation(quickCaptureComposerAnimation) {
                    if drag < -18 {
                        quickCaptureExpanded = true
                    } else if drag > 28 {
                        if quickCaptureExpanded {
                            quickCaptureExpanded = false
                        } else {
                            dismissQuickCaptureComposer()
                        }
                    }
                }
            }
    }

    private var quickCaptureComposerAnimation: Animation {
        .snappy(duration: 0.18, extraBounce: 0)
    }

    private var quickCaptureComposerIsPresented: Bool {
        showShellQuickCapture || showTimelineCapture
    }

    private func presentQuickCaptureComposer(timeline: Bool = false) {
        dismissFloatingMenus()
        quickCaptureExpanded = false
        quickCaptureFields = tasksStore.fields
        quickCaptureProjects = tasksStore.projects
        withAnimation(quickCaptureComposerAnimation) {
            if timeline {
                showTimelineCapture = true
            } else {
                showShellQuickCapture = true
            }
        }
    }

    private func dismissQuickCaptureComposer() {
        withAnimation(quickCaptureComposerAnimation) {
            showShellQuickCapture = false
            showTimelineCapture = false
            quickCaptureExpanded = false
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .schedule, .taskLed:
            TodayView()
        case .tasks:
            TasksView()
        case .projects:
            ProjectsTabView()
        case .stats:
            StatsView()
        case .goals:
            GoalsTabView()
        case .antiTodo:
            AntiTodoListView()
        case .quantifiedSelf:
            QuantifiedSelfView()
        case .pomodoro:
            PomodoroView(onRequestReturnToHub: hubBackActionIfNeeded(for: .pomodoro))
        case .sounds:
            FocusTabView(onRequestReturnToHub: hubBackActionIfNeeded(for: .sounds))
        case .hub, .more:
            HubView()
        }
    }

    /// Leading "back to Hub" for Timer / Sounds only when the user opened that tab from a Hub tool tile.
    private func hubBackActionIfNeeded(for tab: AppTab) -> (() -> Void)? {
        guard auxiliaryTabOpenedFromHub == tab else { return nil }
        return {
            selectedTab = .hub
            auxiliaryTabOpenedFromHub = nil
        }
    }

    private var bottomBar: some View {
        Group {
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: 10) {
                    barContents
                }
            } else {
                barContents
            }
        }
        .padding(.horizontal, CueInLayout.bottomChromeHorizontalMargin)
        // Home-button iPhones (SE 2020/2022) have safeAreaInsets.bottom == 0,
        // so add breathing room above the bezel. Notched / Dynamic-Island phones
        // already have the home-indicator zone; let the glass float into it.
        .padding(.bottom, CueInLayout.barBottomPadding(safeAreaBottom: screenSafeAreaBottom))
        .offset(y: CueInLayout.bottomChromeYOffset(safeAreaBottom: screenSafeAreaBottom))
        .ignoresSafeArea(edges: .bottom)
    }

    private var devNotebookFloatingControl: some View {
        Group {
            if showDevNotebookCaptureButton
                && !shellSheetsBlockDevCapture
                && !showDevCaptureSheet
                && !devNotebookContext.hubNotebookSheetPresented {
                DevNotebookFloatingButton {
                    showDevCaptureSheet = true
                }
                .padding(.leading, 16)
                // Sit just above the floating tab bar (not aligned with the taller trailing FAB column).
                .padding(
                    .bottom,
                    CueInLayout.floatingBarHeight
                        + CueInLayout.barBottomPadding(safeAreaBottom: screenSafeAreaBottom)
                        + 8
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .ignoresSafeArea(edges: .bottom)
                .zIndex(1)
                .allowsHitTesting(true)
            }
        }
    }

    /// Hide the dev capture control while primary shell sheets are up (avoids stacked presentations).
    private var shellSheetsBlockDevCapture: Bool {
        showShellQuickCapture
            || showAntiTodoCapture
            || showFabBlockLibrary
            || showHubOverflowSheet
            || showStatsOverflowSheet
            || auxiliaryTaskSheet != nil
            || showExecutionSheet
            || showTimelineCapture
    }

    /// Clears the floating tab bar + FAB column using the same heights as on-screen chrome.
    private var shellToastBottomInset: CGFloat {
        let showTaskLedExecution = selectedTab == .taskLed && shouldShowFloatingExecutionButton
        let fabColumnHeight: CGFloat = showTaskLedExecution
            ? CueInLayout.fabExecutionDiameter + CueInLayout.floatingFabVerticalSpacing + CueInLayout.fabPlusDiameter
            : CueInLayout.fabPlusDiameter
        let chromeHeight = max(CueInLayout.floatingBarHeight, fabColumnHeight)
        return chromeHeight
            + CueInLayout.barBottomPadding(safeAreaBottom: screenSafeAreaBottom)
            + CueInLayout.bottomChromeYOffset(safeAreaBottom: screenSafeAreaBottom)
            + 8
    }

    private var bottomFeedbackAndBar: some View {
        ZStack(alignment: .bottom) {
            if let toast = toastCenter.toast {
                CueInUndoToast(
                    icon: toast.icon,
                    title: toast.title,
                    message: toast.message,
                    tint: toast.tint,
                    undoTitle: toast.undoTitle,
                    style: toast.style,
                    actions: toast.actions,
                    onUndo: { toastCenter.performUndo(for: toast) },
                    onDismiss: { toastCenter.dismiss(id: toast.id) }
                )
                .accessibilityLabel("\(toast.title), \(toast.message), \(toast.undoTitle)")
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.bottom, shellToastBottomInset)
                .zIndex(2)
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.98)))
            }

            bottomBar
                .zIndex(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(edges: .bottom)
    }

    private var barContents: some View {
        HStack(alignment: .bottom, spacing: CueInLayout.bottomChromeSidecarSpacing) {
            FloatingTabBar(selectedTab: $selectedTab, tabs: visibleTabs)
            floatingFabColumn
        }
    }

    private var visibleTabs: [AppTab] {
        AppTab.storedTabs(from: storedTabsRaw)
    }

    private var resolvedSelectedTab: AppTab {
        visibleTabs.contains(selectedTab) ? selectedTab : (visibleTabs.first ?? .hub)
    }

    private var launchSelectedTab: AppTab {
        if todayViewModel.hasFormulaRunStarted, visibleTabs.contains(.schedule) {
            return .schedule
        }

        let migratedRaw = AppTab.migrateLegacyTabToken(storedSelectedTabRaw)
        if let storedTab = AppTab(rawValue: migratedRaw), visibleTabs.contains(storedTab) {
            return storedTab
        }

        return resolvedSelectedTab
    }

    private var floatingPlusAccessibilityLabel: String {
        switch selectedTab {
        case .schedule: return "Add time block"
        case .antiTodo: return "Add anti to-do"
        case .quantifiedSelf: return "New tracker"
        case .pomodoro, .sounds: return "Quick capture"
        default: return "Add task"
        }
    }

    private var floatingPlusAccessibilityHint: String? {
        switch selectedTab {
        case .antiTodo:
            return "Adds something you are choosing not to do."
        case .quantifiedSelf:
            return "Opens the new tracker sheet for Measures."
        case .schedule:
            if todayMode == .formulaBased, todayViewModel.hasFormulaRunStarted {
                return "Opens the add menu for your TimeMap."
            }
            return nil
        default:
            return nil
        }
    }

    /// TimeMap tab after the day has been started: + opens the block menu instead of inserting immediately.
    private var schedulePlusOpensAddMenu: Bool {
        selectedTab == .schedule
            && todayMode == .formulaBased
            && todayViewModel.hasFormulaRunStarted
    }

    private var floatingFabColumn: some View {
        let showTaskLedExecution = selectedTab == .taskLed && shouldShowFloatingExecutionButton
        let rows = fabOverflowRows
        let showTasksCompleteUndo = selectedTab == .tasks && tasksStore.pendingCompleteUndoSnapshot != nil
        return VStack(spacing: CueInLayout.floatingFabVerticalSpacing) {
            if showTasksCompleteUndo {
                TasksFloatingCompleteUndoChip {
                    dismissFloatingMenus()
                    tasksStore.consumeCompleteUndo()
                }
                .transition(
                    .asymmetric(
                        insertion: .offset(y: 12).combined(with: .opacity).combined(with: .scale(scale: 0.9, anchor: .bottom)),
                        removal: .opacity.combined(with: .scale(scale: 0.94, anchor: .bottom))
                    )
                )
            }
            if showTaskLedExecution {
                FloatingLightningButton {
                    dismissFabOverflow()
                    showExecutionSheet = true
                }
                .transition(
                    .asymmetric(
                        insertion: fabInsertionTransition,
                        removal: fabRemovalTransition
                    )
                )
            }
            FloatingPlusButton(
                onTap: {
                    if schedulePlusOpensAddMenu {
                        toggleScheduleAddMenu()
                        return
                    }
                    dismissFloatingMenus()
                    if selectedTab == .antiTodo {
                        showAntiTodoCapture = true
                    } else if selectedTab == .quantifiedSelf {
                        NotificationCenter.default.post(name: .cueInShowAddMeasureTracker, object: nil)
                    } else if selectedTab == .schedule, todayMode == .formulaBased {
                        todayViewModel.insertFormulaBlock(
                            title: "New Block",
                            type: .focus,
                            flowMode: .blocking,
                            durationMinutes: 45
                        )
                    } else {
                        presentQuickCaptureComposer()
                    }
                },
                onLongPress: {
                    if schedulePlusOpensAddMenu {
                        toggleScheduleAddMenu()
                        return
                    }
                    guard !rows.isEmpty else { return }
                    dismissQuickBlockNowMenu()
                    withAnimation(ShellFabMotion.spring) {
                        fabOverflowPresented = true
                    }
                },
                accessibilityLabelText: floatingPlusAccessibilityLabel,
                accessibilityHintOverride: floatingPlusAccessibilityHint
            )
        }
        // Menu lives in a non-layout overlay so the tab bar height never jumps when it opens.
        .overlay(alignment: .bottomTrailing) {
            if fabOverflowPresented, !rows.isEmpty {
                ShellFabOverflowMenu(rows: rows)
                    .offset(y: -(CueInLayout.fabPlusDiameter + 12))
            }
            if quickBlockNowMenuPresented {
                FormulaBlockNowMenu(
                    title: $quickBlockNowTitle,
                    onPickDuration: { minutes in
                        let title = quickBlockNowTitle
                        quickBlockNowTitle = ""
                        dismissQuickBlockNowMenu()
                        todayViewModel.insertImmediateFormulaBlock(title: title, durationMinutes: minutes)
                    },
                    onDismiss: { dismissQuickBlockNowMenu() }
                )
                .offset(y: -(CueInLayout.fabPlusDiameter + 12))
            }
        }
        .animation(fabSpring, value: showTaskLedExecution)
        .animation(fabSpring, value: showTasksCompleteUndo)
        .dynamicTypeSize(.xSmall ... .large)
    }

    private func dismissFabOverflow() {
        guard fabOverflowPresented else { return }
        withAnimation(ShellFabMotion.spring) {
            fabOverflowPresented = false
        }
    }

    private func dismissQuickBlockNowMenu() {
        guard quickBlockNowMenuPresented else { return }
        withAnimation(ShellFabMotion.spring) {
            quickBlockNowMenuPresented = false
        }
    }

    private func dismissFloatingMenus() {
        dismissFabOverflow()
        dismissQuickBlockNowMenu()
    }

    private func toggleScheduleAddMenu() {
        guard schedulePlusOpensAddMenu, !fabOverflowRows.isEmpty else { return }
        if fabOverflowPresented {
            dismissFabOverflow()
            return
        }
        dismissQuickBlockNowMenu()
        withAnimation(ShellFabMotion.spring) {
            fabOverflowPresented = true
        }
    }

    private var fabSpring: Animation {
        .spring(response: 0.58, dampingFraction: 0.88, blendDuration: 0.22)
    }

    private var fabInsertionTransition: AnyTransition {
        .offset(y: 26)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.88, anchor: .bottom))
    }

    private var fabRemovalTransition: AnyTransition {
        .offset(y: 10)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.94, anchor: .bottom))
    }

    // MARK: - FAB overflow (long-press)

    private var fabOverflowRows: [ShellFabOverflowMenu.Row] {
        switch selectedTab {
        case .schedule:
            return todayMode == .formulaBased ? algorithmFabOverflowRows : []
        case .taskLed:
            return todayMode == .taskLed ? taskLedFabOverflowRows : []
        case .tasks:
            return tasksFabOverflowRows
        case .projects:
            return projectsFabOverflowRows
        case .stats:
            return statsFabOverflowRows
        case .antiTodo, .quantifiedSelf, .pomodoro, .sounds:
            return []
        case .goals, .hub, .more:
            return hubFabOverflowRows
        }
    }

    private var algorithmFabOverflowRows: [ShellFabOverflowMenu.Row] {
        var rows: [ShellFabOverflowMenu.Row] = []

        if todayViewModel.isFormulaRunLive, !todayViewModel.isFormulaSchedulePaused {
            rows.append(
                .init(
                    icon: "exclamationmark.triangle.fill",
                    title: "Block right now",
                    subtitle: "Drop in a quick interruption",
                    tint: Color(red: 1.0, green: 0.63, blue: 0.25)
                ) {
                    dismissFabOverflow()
                    quickBlockNowTitle = ""
                    withAnimation(ShellFabMotion.spring) {
                        quickBlockNowMenuPresented = true
                    }
                }
            )
        }

        rows += [
            .init(icon: "rectangle.stack.fill.badge.plus", title: "New block", subtitle: "Insert a fresh time block") {
                dismissFabOverflow()
                todayViewModel.insertFormulaBlock(
                    title: "New Block",
                    type: .focus,
                    flowMode: .blocking,
                    durationMinutes: 45
                )
            },
            .init(icon: "books.vertical.fill", title: "Block library", subtitle: "Saved shapes and samples") {
                dismissFabOverflow()
                showFabBlockLibrary = true
            },
            .init(icon: "plus.circle.fill", title: "New task", subtitle: "Add to your task list, not on a time block") {
                dismissFabOverflow()
                deferPresentation { presentQuickCaptureComposer() }
            },
            .init(icon: "arrow.triangle.2.circlepath", title: "Change schedule", subtitle: "Pick a different day framework") {
                dismissFabOverflow()
                deferPresentation {
                    NotificationCenter.default.post(name: .cueInShowTodayFormulaPicker, object: nil)
                }
            },
            .init(icon: "repeat", title: "Routine block", subtitle: "Repeatable routine slice") {
                dismissFabOverflow()
                todayViewModel.insertFormulaBlock(
                    title: "Routine Block",
                    type: .routine,
                    flowMode: .blocking,
                    durationMinutes: 30,
                    tasks: [
                        DayTask(title: "First step", isPrimary: true, isRepeating: true)
                    ],
                    isRepeatable: true
                )
            },
            .init(icon: "bolt.fill", title: "Quick item", subtitle: "Small flowing slice") {
                dismissFabOverflow()
                todayViewModel.insertFormulaBlock(
                    title: "Quick Item",
                    type: .mini,
                    flowMode: .flowing,
                    durationMinutes: 10
                )
            },
        ]
        return rows
    }

    private var taskLedFabOverflowRows: [ShellFabOverflowMenu.Row] {
        [
            .init(icon: "calendar.day.timeline.left", title: "Timeline capture", subtitle: "Add straight to the day stream") {
                dismissFabOverflow()
                deferPresentation {
                    presentQuickCaptureComposer(timeline: true)
                }
            },
        ]
    }

    private var tasksFabOverflowRows: [ShellFabOverflowMenu.Row] {
        [
            .init(icon: "folder.badge.plus", title: "New project", subtitle: "Organize work under a project") {
                dismissFabOverflow()
                auxiliaryTaskSheet = .createProject
            },
            .init(icon: "square.grid.2x2.fill", title: "New field", subtitle: "Add an area to group projects") {
                dismissFabOverflow()
                auxiliaryTaskSheet = .createField
            },
        ]
    }

    private var projectsFabOverflowRows: [ShellFabOverflowMenu.Row] {
        [
            .init(icon: "folder.badge.plus", title: "New project", subtitle: "Start a new project") {
                dismissFabOverflow()
                auxiliaryTaskSheet = .createProject
            },
        ]
    }

    private var statsFabOverflowRows: [ShellFabOverflowMenu.Row] {
        [
            .init(icon: "square.and.pencil", title: "Quick log", subtitle: "Record a data point") {
                dismissFabOverflow()
                showStatsOverflowSheet = true
            },
            .init(icon: "note.text", title: "Add note", subtitle: "Attach a note to today") {
                dismissFabOverflow()
                showStatsOverflowSheet = true
            },
        ]
    }

    private var hubFabOverflowRows: [ShellFabOverflowMenu.Row] {
        [
            .init(icon: "target", title: "New goal", subtitle: "Define a grand goal and strategy") {
                dismissFabOverflow()
                NotificationCenter.default.post(name: .cueInShowCreateGoal, object: nil)
            },
            .init(icon: "doc.text.fill", title: "New schedule", subtitle: "Build a day template") {
                dismissFabOverflow()
                showHubOverflowSheet = true
            },
            .init(icon: "gearshape.fill", title: "Settings", subtitle: "App preferences") {
                dismissFabOverflow()
                showHubOverflowSheet = true
            },
        ]
    }

    private var hubOverflowCreateSheet: some View {
        CueInBottomSheet(title: "Create", onDismiss: { showHubOverflowSheet = false }) {
            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                SheetActionRow(
                    icon: "doc.text.fill",
                    title: "New Schedule",
                    subtitle: "Build a day template"
                ) {
                    showHubOverflowSheet = false
                }

                SheetActionRow(
                    icon: "gearshape.fill",
                    title: "Settings",
                    subtitle: "App preferences"
                ) {
                    showHubOverflowSheet = false
                }
            }
        }
    }

    private var statsOverflowPlaceholderSheet: some View {
        CueInBottomSheet(title: "Log entry", onDismiss: { showStatsOverflowSheet = false }) {
            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                SheetActionRow(
                    icon: "square.and.pencil",
                    title: "Quick Log",
                    subtitle: "Record a data point"
                ) {
                    showStatsOverflowSheet = false
                }

                SheetActionRow(
                    icon: "note.text",
                    title: "Add Note",
                    subtitle: "Attach a note to today"
                ) {
                    showStatsOverflowSheet = false
                }
            }
        }
    }

    private func deferPresentation(_ body: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            body()
        }
    }

    private var todayMode: DayEngineMode {
        DayEngineMode(rawValue: todayModeRawValue) ?? .taskLed
    }

    private var shouldShowFloatingExecutionButton: Bool {
        switch todayMode {
        case .taskLed:
            let mode = TodayDisplayPreferences.TaskLedViewMode(rawValue: taskLedViewModeRaw) ?? .timeline
            if mode == .todo { return false }
            return true
        case .formulaBased:
            return false
        }
    }

    private func isTodayDestination(_ tab: AppTab) -> Bool {
        tab.preferredTodayMode != nil
    }

    private func applyNavigationSideEffects(for tab: AppTab) {
        guard let mode = tab.preferredTodayMode else { return }
        if let taskLedViewMode = mode.taskLedViewMode {
            taskLedViewModeRaw = taskLedViewMode.rawValue
        }
        // Single source of truth with tab choice: keep the shared VM aligned with the shell tab,
        // not only `@AppStorage` (otherwise the menu / stale VM fights the navbar).
        todayViewModel.setDayEngineMode(mode.dayEngine)
    }
}

// MARK: - Preference key for safe-area bottom inset

private struct BottomSafeAreaKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FormulaBlockNowMenu: View {
    @Binding var title: String
    let onPickDuration: (Int) -> Void
    let onDismiss: () -> Void

    private let durations = [5, 10, 15, 20, 30, 45]

    var body: some View {
        menuSurface
            .shadow(color: Color.black.opacity(0.30), radius: 22, y: 14)
            .transition(
                .asymmetric(
                    insertion: .opacity
                        .combined(with: .move(edge: .bottom))
                        .combined(with: .scale(scale: 0.94, anchor: .bottomTrailing)),
                    removal: .opacity
                        .combined(with: .scale(scale: 0.97, anchor: .bottomTrailing))
                )
            )
    }

    @ViewBuilder
    private var menuSurface: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 6) {
                menuBody
                    .formulaBlockNowGlassChrome()
            }
        } else {
            menuBody
                .formulaBlockNowGlassChrome()
        }
    }

    private var menuBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Block right now")
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(CueInColors.textPrimary)

                    Text("Choose duration")
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CueInColors.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            TextField("Optional name", text: $title)
                .font(CueInTypography.captionMedium)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.055))
                )
                .foregroundStyle(CueInColors.textPrimary)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ],
                spacing: 6
            ) {
                ForEach(durations, id: \.self) { minutes in
                    Button {
                        onPickDuration(minutes)
                    } label: {
                        Text("\(minutes)m")
                            .font(CueInTypography.captionMedium)
                            .foregroundStyle(CueInColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(minutes == 15 ? 0.12 : 0.06))
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(9)
        .frame(width: 224, alignment: .leading)
    }
}

private struct FormulaBlockNowGlassChrome: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if #available(iOS 26.0, *) {
            content
                .clipShape(shape)
                .glassEffect(
                    .regular.tint(Color(red: 1.0, green: 0.63, blue: 0.25).opacity(0.15)).interactive(),
                    in: shape
                )
        } else {
            content
                .clipShape(shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
                }
        }
    }
}

private extension View {
    func formulaBlockNowGlassChrome() -> some View {
        modifier(FormulaBlockNowGlassChrome())
    }
}

#Preview {
    AppShellView()
        .cueInPreferredColorScheme()
}

#endif
