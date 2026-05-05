import SwiftUI

// MARK: - AppShellView
/// Root container with content flowing under a floating bottom control cluster.

struct AppShellView: View {
    private enum TodaySheetRoute {
        case formulaPicker
        case timelineQuickCapture
        case scheduleBlockTask
    }

    @AppStorage(DayEngineMode.storageKey) private var todayModeRawValue = DayEngineMode.taskLed.rawValue
    @AppStorage(TodayDisplayPreferences.taskLedViewMode) private var taskLedViewModeRaw
        = TodayDisplayPreferences.TaskLedViewMode.timeline.rawValue
    @State private var selectedTab: AppTab = .today
    @State private var showAddSheet = false
    @State private var showExecutionSheet = false
    @State private var showTimelineCapture = false
    @State private var showScheduleBlockTaskSheet = false
    @State private var screenSafeAreaBottom: CGFloat = 0
    @State private var pendingTodaySheetRoute: TodaySheetRoute?
    @State private var showDevCaptureSheet = false
    @AppStorage("cuein.devNotebook.showCaptureButton") private var showDevNotebookCaptureButton = false
    @Bindable private var toastCenter = CueInToastCenter.shared
    @Bindable private var todayViewModel = TodayViewModel.shared

    var body: some View {
        ZStack {
            CueInColors.background.ignoresSafeArea()
            // Read safe area once so the bar can adapt to home-button vs notched phones.
            Color.clear
                .ignoresSafeArea()
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: BottomSafeAreaKey.self,
                            value: geo.safeAreaInsets.bottom
                        )
                    }
                    .ignoresSafeArea()
                )
                .onPreferenceChange(BottomSafeAreaKey.self) { screenSafeAreaBottom = $0 }
            tabContent
            bottomFeedbackAndBar
            devNotebookFloatingControl
        }
        .onAppear {
            DevNotebookContext.shared.selectedTab = selectedTab
        }
        .onChange(of: selectedTab) { _, newValue in
            DevNotebookContext.shared.selectedTab = newValue
            DevNotebookContext.shared.screenLabel = nil
        }
        .sheet(isPresented: $showAddSheet, onDismiss: handleAddSheetDismiss) {
            sheetContent
                .presentationDetents(sheetDetents)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showExecutionSheet) {
            ExecutionActionSheet(onDismiss: { showExecutionSheet = false })
                .presentationDetents([.medium])
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTimelineCapture) {
            QuickCaptureSheet(
                onDismiss: { showTimelineCapture = false },
                onExpand:  { _ in showTimelineCapture = false }
            )
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showScheduleBlockTaskSheet) {
            ScheduleQuickAddTaskSheet(
                blocks: todayViewModel.todayScheduleBlocks,
                onAdd: { blockID, title in
                    todayViewModel.addTemplateTaskToFormulaBlock(blockID: blockID, title: title)
                    showScheduleBlockTaskSheet = false
                },
                onCancel: { showScheduleBlockTaskSheet = false }
            )
            .presentationDetents([.medium])
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDevCaptureSheet) {
            DevNotebookCaptureSheet(isPresented: $showDevCaptureSheet, defaultKind: .moduleIdea) { kind, body in
                let snap = DevNotebookContext.shared.makeSnapshot()
                DevNotebookStore.shared.add(DevNotebookEntry(
                    kind: kind,
                    body: body,
                    moduleLabel: snap.moduleLabel,
                    contextLine: snap.contextLine
                ))
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .animation(.easeInOut(duration: 0.18), value: selectedTab)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .today:  TodayView()
        case .tasks:  TasksView()
        case .stats:  StatsView()
        case .hub:    HubView()
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
        .padding(.horizontal, 16)
        // Home-button iPhones (SE 2020/2022) have safeAreaInsets.bottom == 0,
        // so add breathing room above the bezel. Notched / Dynamic-Island phones
        // already have the home-indicator zone; let the glass float into it.
        .padding(.bottom, CueInLayout.barBottomPadding(safeAreaBottom: screenSafeAreaBottom))
        .offset(y: screenSafeAreaBottom > 0 ? 9 : 3)
        .ignoresSafeArea(edges: .bottom)
    }

    private var devNotebookFloatingControl: some View {
        Group {
            if showDevNotebookCaptureButton && !shellSheetsBlockDevCapture && !showDevCaptureSheet {
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
                .zIndex(1)
                .allowsHitTesting(true)
            }
        }
    }

    /// Hide the dev capture control while primary shell sheets are up (avoids stacked presentations).
    private var shellSheetsBlockDevCapture: Bool {
        showAddSheet || showExecutionSheet || showTimelineCapture || showScheduleBlockTaskSheet
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
                // Keep the toast above the tallest FAB column + tab bar.
                .padding(.bottom, max(CueInLayout.floatingBarHeight, CueInLayout.stackedFabColumnHeight) + 16)
                .zIndex(2)
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.98)))
            }

            bottomBar
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var barContents: some View {
        HStack(alignment: .bottom, spacing: 12) {
            FloatingTabBar(selectedTab: $selectedTab, todayPresentation: todayTabBarPresentation)
            floatingFabColumn
        }
    }

    private var todayTabBarPresentation: TodayTabBarPresentation {
        let taskLedMode = TodayDisplayPreferences.TaskLedViewMode(rawValue: taskLedViewModeRaw) ?? .timeline
        return .resolved(dayEngine: todayMode, taskLedViewMode: taskLedMode)
    }

    /// Trailing **two separate** circular actions: execution (Today only) above add.
    /// Formula preview starts from Today chrome; after a schedule starts, the floating bolt
    /// becomes the schedule action entry point above add.
    private var floatingFabColumn: some View {
        let showExecution = selectedTab == .today && shouldShowFloatingExecutionButton
        return VStack(spacing: CueInLayout.floatingFabVerticalSpacing) {
            if showExecution {
                FloatingLightningButton { showExecutionSheet = true }
                    .transition(
                        .asymmetric(
                            insertion: fabInsertionTransition,
                            removal: fabRemovalTransition
                        )
                    )
            }
            FloatingPlusButton { showAddSheet = true }
        }
        .animation(fabSpring, value: showExecution)
        .dynamicTypeSize(.xSmall ... .large)
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

    // MARK: - Sheets

    @ViewBuilder
    private var sheetContent: some View {
        switch selectedTab {
        case .today:
            if todayMode == .taskLed {
                TimelineActionSheet(
                    onAddTask: {
                        pendingTodaySheetRoute = .timelineQuickCapture
                        showAddSheet = false
                    },
                    onDismiss: { showAddSheet = false }
                )
            } else {
                AddItemSheetView(
                    onChangeFormula: {
                        pendingTodaySheetRoute = .formulaPicker
                        showAddSheet = false
                    },
                    onAddBlock: {
                        todayViewModel.insertFormulaBlock(
                            title: "New Block",
                            type: .focus,
                            flowMode: .blocking,
                            durationMinutes: 45
                        )
                        showAddSheet = false
                    },
                    onAddTask: {
                        pendingTodaySheetRoute = .scheduleBlockTask
                        showAddSheet = false
                    },
                    onAddRoutineBlock: {
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
                        showAddSheet = false
                    },
                    onAddQuickItem: {
                        todayViewModel.insertFormulaBlock(
                            title: "Quick Item",
                            type: .mini,
                            flowMode: .flowing,
                            durationMinutes: 10
                        )
                        showAddSheet = false
                    },
                    onDismiss: { showAddSheet = false }
                )
            }
        case .tasks:
            QuickCaptureSheet(
                onDismiss: { showAddSheet = false },
                onExpand:  { _ in showAddSheet = false }
            )
        case .stats:
            placeholderSheet(title: "Log Entry", items: [
                ("square.and.pencil", "Quick Log",  "Record a data point"),
                ("note.text",         "Add Note",   "Attach a note to today"),
            ])
        case .hub:
            placeholderSheet(title: "Create", items: [
                ("target",        "New Goal",    "Define a goal"),
                ("doc.text.fill", "New Schedule", "Build a day template"),
                ("gearshape.fill","Settings",    "App preferences"),
            ])
        }
    }

    @ViewBuilder
    private func placeholderSheet(title: String, items: [(String, String, String)]) -> some View {
        CueInBottomSheet(title: title, onDismiss: { showAddSheet = false }) {
            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                ForEach(items, id: \.1) { item in
                    SheetActionRow(icon: item.0, title: item.1, subtitle: item.2) {
                        showAddSheet = false
                    }
                }
            }
        }
    }

    private func handleAddSheetDismiss() {
        guard selectedTab == .today, let route = pendingTodaySheetRoute else { return }
        pendingTodaySheetRoute = nil

        switch route {
        case .formulaPicker:
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                NotificationCenter.default.post(name: .cueInShowTodayFormulaPicker, object: nil)
            }
        case .timelineQuickCapture:
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                showTimelineCapture = true
            }
        case .scheduleBlockTask:
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                showScheduleBlockTaskSheet = true
            }
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
            return todayViewModel.hasFormulaRunStarted
        }
    }

    private var sheetDetents: Set<PresentationDetent> {
        selectedTab == .tasks ? [.medium, .large] : [.medium]
    }
}

// MARK: - Preference key for safe-area bottom inset

private struct BottomSafeAreaKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    AppShellView()
        .preferredColorScheme(.dark)
}
