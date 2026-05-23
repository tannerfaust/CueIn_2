import SwiftUI

// MARK: - TodayView
/// The Today tab — Day Engine. Content extends behind the tab bar.

struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = TodayViewModel.shared
    @Bindable private var tasksStore = TasksStore.shared
    @State private var showFormulaPickerSheet = false
    @State private var showFormulaScheduleSaveSheet = false
    @State private var showSettingsSheet = false
    @State private var showScheduleStartSheet = false
    /// Frozen “now” for the start sheet preflight; without this, every parent tick re-runs preflight with a later `Date()` and the run window shrinks (issues can appear seconds after open).
    @State private var scheduleStartRunAnchor: Date?
    @State private var draftScheduleEnd = Date().addingTimeInterval(8 * 3600)
    @State private var timelineEditorRoute: TaskTimelineEditorRoute?
    @State private var draggedScheduleBlockID: UUID?
    @State private var blockTitleEdit: BlockEditSheetItem?
    @State private var blockAddTask: IdentifiedBlockID?
    @State private var blockDeleteConfirm: IdentifiedBlockID?
    @State private var isJiggleRearrangeMode = false
    @State private var showTimeblockFocus = false
    @State private var focusEntryBlockID: UUID?
    @AppStorage(TodayDisplayPreferences.showScheduleStartTime) private var showScheduleStartTime = true
    @AppStorage(TodayDisplayPreferences.showScheduleDuration) private var showScheduleDuration = false
    @AppStorage(TodayDisplayPreferences.showScheduleTimeRange) private var showScheduleTimeRange = false
    @AppStorage(TodayDisplayPreferences.timelineHourHeight)  private var timelineHourHeight = TodayDisplayPreferences.timelineHourHeightDefault
    @AppStorage(TodayDisplayPreferences.timelineLayoutMode)  private var timelineLayoutModeRaw = TodayDisplayPreferences.TimelineLayoutMode.vertical.rawValue
    @AppStorage(TodayDisplayPreferences.taskLedViewMode) private var taskLedViewModeRaw = TodayDisplayPreferences.TaskLedViewMode.timeline.rawValue
    @AppStorage(TodayDisplayPreferences.scheduleDesign) private var scheduleDesignRaw = TodayDisplayPreferences.ScheduleDesign.glass.rawValue
    @AppStorage(TodayDisplayPreferences.runningLineStyle) private var runningLineStyleRaw = TodayDisplayPreferences.RunningLineStyle.minimal.rawValue
    @AppStorage(TodayDisplayPreferences.activeBlockEmphasis) private var activeBlockEmphasisRaw
        = TodayDisplayPreferences.ActiveBlockEmphasis.brand.rawValue
    @AppStorage(TodayDisplayPreferences.runningLineSize) private var runningLineSizeRaw
        = TodayDisplayPreferences.RunningLineSize.standard.rawValue
    @AppStorage(TodayDisplayPreferences.runningLineBarWeight) private var runningLineBarWeightRaw
        = TodayDisplayPreferences.RunningLineBarWeight.standard.rawValue
    @AppStorage(TodayDisplayPreferences.runningLineFrostedCard) private var runningLineFrostedCard = true
    @AppStorage(TodayDisplayPreferences.runningLineShowBlockTitle) private var runningLineShowBlockTitle = true
    @AppStorage(TodayDisplayPreferences.runningLineShowDayPercent) private var runningLineShowDayPercent = true
    @AppStorage(TodayDisplayPreferences.schedulePauseBehavior) private var schedulePauseBehaviorRaw
        = TodayDisplayPreferences.SchedulePauseBehavior.preserveLength.rawValue
    @AppStorage(TodayDisplayPreferences.scheduleShowsPagePlaybackControl) private var scheduleShowsPagePlaybackControl = false
    @AppStorage(TodayDisplayPreferences.scheduleBlockTimerStyle) private var scheduleBlockTimerStyleRaw
        = TodayDisplayPreferences.ScheduleBlockTimerStyle.ring.rawValue
    @AppStorage(TodayDisplayPreferences.scheduleBlockTimerShowsSeconds) private var scheduleBlockTimerShowsSeconds = false
    @AppStorage(TodayDisplayPreferences.canvasDotsBackground) private var canvasDotsBackground = false
    @AppStorage(TodayDisplayPreferences.pullsTasksFromExecutionPool) private var pullsTasksFromExecutionPool = true
    @AppStorage(TodayDisplayPreferences.enableCategoryTracking) private var enableCategoryTracking = false
    @AppStorage(TodayDisplayPreferences.todoViewShowInfoBlock) private var todoViewShowInfoBlock = true
    @AppStorage(TodayDisplayPreferences.todoSummaryPlacement) private var todoSummaryPlacementRaw
        = TodayDisplayPreferences.TodoSummaryPlacement.inList.rawValue
    @AppStorage(TodayDisplayPreferences.todoChromeSummaryMetric) private var todoChromeSummaryMetricRaw
        = TodayDisplayPreferences.TodoChromeSummaryMetric.openAndPlanned.rawValue

    private var timelineLayoutMode: TodayDisplayPreferences.TimelineLayoutMode {
        TodayDisplayPreferences.TimelineLayoutMode(rawValue: timelineLayoutModeRaw) ?? .vertical
    }

    private var taskLedViewMode: TodayDisplayPreferences.TaskLedViewMode {
        TodayDisplayPreferences.TaskLedViewMode(rawValue: taskLedViewModeRaw) ?? .timeline
    }

    private var todoSummaryPlacement: TodayDisplayPreferences.TodoSummaryPlacement {
        TodayDisplayPreferences.migratedTodoSummaryPlacement(from: todoSummaryPlacementRaw)
    }

    private var todoChromeSummaryMetric: TodayDisplayPreferences.TodoChromeSummaryMetric {
        TodayDisplayPreferences.migratedTodoChromeSummaryMetric(from: todoChromeSummaryMetricRaw)
    }

    private var todoOpenTasksForChromeSort: [TaskItem] {
        tasksStore.todayTasks.filter { !$0.isCompleted }
    }

    private var scheduleDesign: TodayDisplayPreferences.ScheduleDesign {
        TodayDisplayPreferences.migratedScheduleDesign(from: scheduleDesignRaw)
    }

    private var runningLineStyle: TodayDisplayPreferences.RunningLineStyle {
        TodayDisplayPreferences.migratedRunningLineStyle(from: runningLineStyleRaw)
    }

    /// Paused / stopped TimeMaps use a neutral running-line fill instead of block colors.
    private var runningLineGreyFillWhilePausedReplan: Bool {
        viewModel.isFormulaSchedulePaused || viewModel.isFormulaRunStopped
    }

    private var scheduleBlockTimerStyle: TodayDisplayPreferences.ScheduleBlockTimerStyle {
        TodayDisplayPreferences.migratedScheduleBlockTimerStyle(from: scheduleBlockTimerStyleRaw)
    }

    private var todayChromeTitle: String {
        if viewModel.isFormulaMode {
            return viewModel.formulaScheduleNavigationTitle
        }
        if viewModel.isTaskLedMode {
            return taskLedViewMode.title
        }
        return "Today"
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isTaskLedMode {
                    taskLedContent
                } else {
                    ZStack {
                        if canvasDotsBackground {
                            CanvasDotsBackgroundView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        ScrollViewReader { proxy in
                            ScrollView(.vertical, showsIndicators: false) {
                                VStack(alignment: .leading, spacing: CueInSpacing.md) {
                                    if viewModel.hasFormulaRunStarted {
                                        RunningLineView(
                                            dayProgress: viewModel.dayProgress,
                                            remainingLabel: viewModel.runningLineRemainingLabel,
                                            currentBlockTitle: viewModel.runningLineTitle,
                                            style: runningLineStyle,
                                            accentColors: viewModel.runningLineProgressAccentPalette,
                                            blockSegments: viewModel.runningLineBlockSegments,
                                            greyFillWhilePausedReplan: runningLineGreyFillWhilePausedReplan,
                                            isStopped: viewModel.isFormulaRunStopped
                                        )
                                    } else if !viewModel.shouldShowScheduleEmptyCallout,
                                        viewModel.isFormulaRunStopped,
                                        !viewModel.headerStatusLine.isEmpty {
                                        Text(viewModel.headerStatusLine)
                                            .font(CueInTypography.caption)
                                            .foregroundStyle(CueInColors.textTertiary)
                                            .padding(.horizontal, CueInSpacing.screenHorizontal)
                                            .padding(.top, CueInSpacing.xs)
                                    }

                                    if viewModel.isFormulaPreviewing,
                                        viewModel.hasFormulaTemplate,
                                        !viewModel.shouldShowScheduleEmptyCallout {
                                        FormulaSchedulePreviewStatsBar(
                                            blocks: viewModel.todayScheduleBlocks,
                                            showsSaveButton: viewModel.isFormulaPreviewScheduleDirty,
                                            onSave: { showFormulaScheduleSaveSheet = true }
                                        )
                                        .padding(.horizontal, CueInSpacing.screenHorizontal)
                                    }

                                    if viewModel.shouldShowScheduleEmptyCallout {
                                        ScheduleEmptyCalloutView()
                                    } else {
                                        ScheduleBlockTimelineView(
                                            blocks: viewModel.todayScheduleBlocks,
                                            currentBlockID: viewModel.currentBlockID,
                                            scheduleDesign: scheduleDesign,
                                            useCanvasLiquidGlass: canvasDotsBackground,
                                            frozenLiveProgressDate: viewModel.formulaSchedulePausedAt,
                                            showsScheduledTime: viewModel.hasFormulaRunStarted,
                                            showsStartTime: showScheduleStartTime,
                                            showsDuration: showScheduleDuration,
                                            showsTimeRange: showScheduleTimeRange,
                                            showsFinishControl: viewModel.isFormulaRunLive || viewModel.isTimelessRunLive,
                                            showsCompletedToggle: viewModel.isFormulaMode || viewModel.isTimelessRunLive,
                                            isLiveRun: viewModel.isFormulaRunLive || viewModel.isTimelessRunLive,
                                            timerStyle: scheduleBlockTimerStyle,
                                            showsTimerSeconds: scheduleBlockTimerShowsSeconds,
                                            draggedBlockID: $draggedScheduleBlockID,
                                            canRearrangeBlock: { blockID in
                                                viewModel.canRearrangeFormulaBlock(blockID: blockID)
                                            },
                                            canUseBlockContextMenu: { blockID in
                                                viewModel.canUseBlockContextMenu(blockID: blockID)
                                            },
                                            canDeleteFromContextMenu: { blockID in
                                                viewModel.canDeleteFormulaBlock(blockID: blockID)
                                            },
                                            onMoveBlock: { sourceID, targetID in
                                                viewModel.moveFormulaBlock(sourceID: sourceID, before: targetID)
                                            },
                                            onToggleTask: { blockID, taskID in
                                                viewModel.toggleTask(blockID: blockID, taskID: taskID)
                                            },
                                            onCompleteBlock: { blockID in
                                                viewModel.completeBlock(blockID: blockID)
                                            },
                                            onFinishBlockKeepingPending: { blockID in
                                                viewModel.finishBlockKeepingPending(blockID: blockID)
                                            },
                                            onRevertCompletedBlock: { blockID in
                                                viewModel.revertCompletedBlock(blockID: blockID)
                                            },
                                            onContextEdit: { block in
                                                blockTitleEdit = BlockEditSheetItem(block: block)
                                            },
                                            onContextAddTask: { blockID in
                                                blockAddTask = IdentifiedBlockID(id: blockID)
                                            },
                                            onContextRearrange: { _ in
                                                isJiggleRearrangeMode = true
                                            },
                                            onContextDelete: { blockID in
                                                blockDeleteConfirm = IdentifiedBlockID(id: blockID)
                                            },
                                            onSwipeCommitDelete: { blockID in
                                                viewModel.deleteFormulaBlock(blockID: blockID)
                                            },
                                            onOpenFocus: {
                                                focusEntryBlockID = viewModel.currentBlockID
                                                showTimeblockFocus = true
                                            },
                                            isJiggleRearrangeMode: isJiggleRearrangeMode
                                        )
                                    }
                                }
                                .padding(.bottom, CueInLayout.scrollBottomInset)
                            }
                            .scrollDisabled(draggedScheduleBlockID != nil)
                            .onChange(of: viewModel.currentBlockID) {
                                scrollToCurrentBlock(using: proxy)
                            }
                            .task {
                                scrollToCurrentBlock(using: proxy)
                            }
                        }
                    }
                }
            }
            .onAppear {
                viewModel.onAppear()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    viewModel.onAppear()
                }
            }
            .onChange(of: pullsTasksFromExecutionPool) { _, _ in
                viewModel.applyExecutionPoolPullPreference()
            }
            .onReceive(NotificationCenter.default.publisher(for: .cueInShowTodayFormulaPicker)) { _ in
                showFormulaPickerSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .cueInShowScheduleStartSetup)) { _ in
                presentScheduleStart()
            }
            .onReceive(NotificationCenter.default.publisher(for: .cueInOpenTimeblockFocus)) { _ in
                guard viewModel.currentBlockID != nil else { return }
                focusEntryBlockID = viewModel.currentBlockID
                showTimeblockFocus = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .cueInApplySavedFormula)) { note in
                guard let raw = note.userInfo?[CueInShellNotification.formulaIDUserInfoKey] as? String,
                      let id = UUID(uuidString: raw)
                else { return }
                viewModel.setDayEngineMode(.formulaBased)
                viewModel.reloadAvailableFormulasFromLibrary()
                viewModel.selectFormula(id)
            }
            .background(CueInColors.background)
            .navigationTitle(todayChromeTitle)
            .cueInNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: CueInToolbarPlacement.topBarTrailing) {
                    if isJiggleRearrangeMode {
                        Button("Done") { isJiggleRearrangeMode = false }
                            .fontWeight(.semibold)
                            .foregroundStyle(CueInColors.textPrimary)
                    }

                    if viewModel.hasFormulaTemplate && viewModel.isFormulaPreviewing {
                        Button("Start") {
                            isJiggleRearrangeMode = false
                            presentScheduleStart()
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(CueInColors.textPrimary)
                    }

                    if scheduleShowsPagePlaybackControl && viewModel.hasFormulaRunStarted {
                        Button {
                            toggleSchedulePlayback()
                        } label: {
                            Image(systemName: (viewModel.isFormulaRunStopped || viewModel.isFormulaSchedulePaused) ? "play.fill" : "pause.fill")
                        }
                        .accessibilityLabel((viewModel.isFormulaRunStopped || viewModel.isFormulaSchedulePaused) ? "Resume TimeMap" : "Pause TimeMap")
                        .foregroundStyle(CueInColors.textPrimary)
                    }

                    todayTodoChromeBeforeTrailing

                    todayOverflowMenu
                }
            }
        }
        .devNotebookScreen(todayChromeTitle)
        .tint(CueInColors.textPrimary)
        .fullScreenCover(isPresented: $showTimeblockFocus) {
            if let entryID = focusEntryBlockID ?? viewModel.currentBlockID ?? viewModel.blocks.first?.id {
                TimeblockFocusModeView(
                    initialBlockID: entryID,
                    frozenProgressDate: viewModel.formulaSchedulePausedAt,
                    showsFinishControl: viewModel.isFormulaRunLive || viewModel.isTimelessRunLive,
                    onDismiss: {
                        focusEntryBlockID = nil
                        showTimeblockFocus = false
                    }
                )
            }
        }
        .sheet(isPresented: $showFormulaPickerSheet) {
                FormulaPickerSheet(
                    formulas: viewModel.availableFormulas,
                    selectedFormulaID: viewModel.selectedFormulaID,
                    onSelect: { formulaID in
                        viewModel.selectFormula(formulaID)
                        showFormulaPickerSheet = false
                    },
                    onNewTimeMap: {
                        showFormulaPickerSheet = false
                        viewModel.createNewUserAlgorithmFromRoutineTemplate()
                    },
                    onDismiss: { showFormulaPickerSheet = false }
                )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(isPresented: $showSettingsSheet) {
            TodaySettingsSheet(
                isTaskLedMode: viewModel.isTaskLedMode,
                taskLedViewModeRaw: $taskLedViewModeRaw,
                timelineLayoutModeRaw: $timelineLayoutModeRaw,
                timelineHourHeight: $timelineHourHeight,
                scheduleDesignRaw: $scheduleDesignRaw,
                runningLineStyleRaw: $runningLineStyleRaw,
                activeBlockEmphasisRaw: $activeBlockEmphasisRaw,
                runningLineSizeRaw: $runningLineSizeRaw,
                runningLineBarWeightRaw: $runningLineBarWeightRaw,
                runningLineFrostedCard: $runningLineFrostedCard,
                runningLineShowBlockTitle: $runningLineShowBlockTitle,
                runningLineShowDayPercent: $runningLineShowDayPercent,
                schedulePauseBehaviorRaw: $schedulePauseBehaviorRaw,
                showScheduleStartTime: $showScheduleStartTime,
                showScheduleDuration: $showScheduleDuration,
                showScheduleTimeRange: $showScheduleTimeRange,
                scheduleBlockTimerStyleRaw: $scheduleBlockTimerStyleRaw,
                scheduleBlockTimerShowsSeconds: $scheduleBlockTimerShowsSeconds,
                pullsTasksFromExecutionPool: $pullsTasksFromExecutionPool,
                canvasDotsBackground: $canvasDotsBackground,
                enableCategoryTracking: $enableCategoryTracking,
                onDismiss: { showSettingsSheet = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(isPresented: $showScheduleStartSheet) {
            let runAnchor = scheduleStartRunAnchor ?? Date()
            let startPreview = viewModel.scheduleStartPreview(targetEnd: draftScheduleEnd, runStart: runAnchor)
            ScheduleStartSetupSheet(
                preview: startPreview,
                draftScheduleEnd: $draftScheduleEnd,
                onStart: { endDate in
                    viewModel.startFormulaDay(targetEnd: endDate)
                    showScheduleStartSheet = false
                },
                onIssueAction: { action in
                    switch action {
                    case .useSafeEnd:
                        break
                    case .unpinBlock(let blockID):
                        viewModel.unpinFormulaBlock(blockID: blockID)
                    case .deleteBlock(let blockID):
                        viewModel.deleteFormulaBlock(blockID: blockID)
                    }
                },
                onCancel: { showScheduleStartSheet = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .onChange(of: showScheduleStartSheet) { _, isOpen in
            if !isOpen { scheduleStartRunAnchor = nil }
        }
        .sheet(item: $timelineEditorRoute, onDismiss: {
            viewModel.syncExecutionTimelineAfterExternalTaskEdit()
        }) { route in
            switch route {
            case .storeTask(let taskItemID):
                TaskDetailSheet(mode: .edit(taskItemID), store: .shared) {
                    timelineEditorRoute = nil
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
            case .executionOnly(let request):
                ExecutionTaskEditorSheet(
                    task: request.task,
                    onSave: { updatedTask in
                        viewModel.updateExecutionTask(dayID: request.dayID, task: updatedTask)
                        timelineEditorRoute = nil
                    },
                    onDelete: {
                        viewModel.deleteExecutionTask(dayID: request.dayID, taskID: request.task.id)
                        timelineEditorRoute = nil
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
            }
        }
        .sheet(isPresented: $showFormulaScheduleSaveSheet) {
            let seed = viewModel.formulaScheduleSaveSheetSeed
            FormulaScheduleSaveSheet(
                initialName: seed.name,
                initialSymbol: seed.symbol,
                initialSummary: seed.summary,
                allowsUpdateExisting: viewModel.isSelectedFormulaUserSavedSchedule,
                scheduleIDExcludedWhenUpdating: viewModel.selectedFormulaID,
                onCancel: { showFormulaScheduleSaveSheet = false },
                onCommit: { name, symbol, summary, intent in
                    if viewModel.saveCurrentPreviewSchedule(
                        name: name,
                        symbol: symbol,
                        summary: summary,
                        intent: intent
                    ) {
                        showFormulaScheduleSaveSheet = false
                    } else {
                        CueInToastCenter.shared.showWarning(
                            icon: "text.badge.xmark",
                            title: "Name already used",
                            message: "That schedule name is taken. Pick another name."
                        )
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(item: $blockTitleEdit) { item in
            ScheduleBlockEditSheet(
                block: item.block,
                availableScopes: viewModel.scheduleMakerTaskScopes,
                onSave: { draft in
                    viewModel.applyFormulaBlockEdits(blockID: item.blockID, draft: draft)
                    blockTitleEdit = nil
                },
                onCancel: { blockTitleEdit = nil }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(item: $blockAddTask) { box in
            ScheduleBlockAddTaskSheet(
                store: tasksStore,
                excludedTaskIDs: excludedPlannerTaskIDs(for: box.id),
                captureDefaultsToToday: true,
                onPickExisting: { item in
                    viewModel.linkPlannerTaskToFormulaBlock(blockID: box.id, item: item)
                    blockAddTask = nil
                },
                onQuickCaptureSaved: { item in
                    viewModel.linkPlannerTaskToFormulaBlock(blockID: box.id, item: item)
                    blockAddTask = nil
                },
                onQuickCaptureExpand: { draft in
                    tasksStore.addTask(draft)
                    viewModel.linkPlannerTaskToFormulaBlock(blockID: box.id, item: draft)
                    blockAddTask = nil
                },
                onDismiss: { blockAddTask = nil }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .confirmationDialog(
            "Delete this block?",
            isPresented: Binding(
                get: { blockDeleteConfirm != nil },
                set: { if !$0 { blockDeleteConfirm = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = blockDeleteConfirm?.id {
                    viewModel.deleteFormulaBlock(blockID: id)
                }
                blockDeleteConfirm = nil
            }
            Button("Cancel", role: .cancel) {
                blockDeleteConfirm = nil
            }
        } message: {
            Text("The rest of the day will be re-timed. This can’t be undone.")
        }
    }

    @ViewBuilder
    private var taskLedContent: some View {
        if taskLedViewMode == .todo {
            TodayTodoView(
                store: tasksStore,
                onOpenTask: { taskID in
                    timelineEditorRoute = .storeTask(taskID)
                }
            )
        } else {
            let timelineDays   = viewModel.executionDays
            let timelineNow    = viewModel.currentTime
            let timelineHeight = CGFloat(timelineHourHeight)

            let toggleTask: (Date, UUID) -> Void = { dayID, taskID in
                viewModel.toggleExecutionTask(dayID: dayID, taskID: taskID)
            }
            let deleteTask: (Date, UUID) -> Void = { dayID, taskID in
                viewModel.deleteExecutionTask(dayID: dayID, taskID: taskID)
            }
            let editTask: (Date, ExecutionTaskCard) -> Void = { dayID, task in
                if let plannerID = task.plannerTaskItemID {
                    timelineEditorRoute = .storeTask(plannerID)
                } else {
                    timelineEditorRoute = .executionOnly(
                        ExecutionTaskEditRequest(dayID: dayID, task: task)
                    )
                }
            }
            let previewMove: (Date, UUID, Date) -> [ExecutionTaskCard] = { dayID, taskID, proposed in
                viewModel.previewExecutionTaskMove(dayID: dayID, taskID: taskID, startDate: proposed)
            }
            let commitMove: (Date, UUID, Date) -> Void = { dayID, taskID, proposed in
                viewModel.moveExecutionTask(dayID: dayID, taskID: taskID, startDate: proposed)
            }

            if timelineLayoutMode == .paged {
                PagedExecutionTimelineView(
                    days: timelineDays,
                    currentTime: timelineNow,
                    hourHeight: timelineHeight,
                    onToggleTask: toggleTask,
                    onDeleteTask: deleteTask,
                    onEditTask: editTask,
                    onPreviewMoveTask: previewMove,
                    onMoveTask: commitMove
                )
            } else {
                ExecutionTimelineView(
                    days: timelineDays,
                    currentTime: timelineNow,
                    hourHeight: timelineHeight,
                    onToggleTask: toggleTask,
                    onDeleteTask: deleteTask,
                    onEditTask: editTask,
                    onPreviewMoveTask: previewMove,
                    onMoveTask: commitMove
                )
            }
        }
    }

    @ViewBuilder
    private var todayTodoChromeBeforeTrailing: some View {
        if viewModel.isTaskLedMode, taskLedViewMode == .todo {
            let showSummaryPill = todoViewShowInfoBlock && todoSummaryPlacement == .inChrome
            let showSort = !todoOpenTasksForChromeSort.isEmpty
            if showSummaryPill || showSort {
                HStack(spacing: CueInSpacing.sm) {
                    if showSummaryPill {
                        TodayTodoChromeSummaryBarPill(
                            metric: todoChromeSummaryMetric,
                            openCount: tasksStore.todayTasks.filter { !$0.isCompleted }.count,
                            completedCount: tasksStore.todayTasks.filter(\.isCompleted).count,
                            totalCount: tasksStore.todayTasks.count,
                            plannedMinutesOpen: tasksStore.todayTasks.filter { !$0.isCompleted }.reduce(0) { $0 + $1.plannedMinutes }
                        )
                    }
                    if showSort {
                        TodayTodoChromeSortMenu(
                            store: tasksStore,
                            tasksToSort: todoOpenTasksForChromeSort
                        )
                    }
                }
            }
        }
    }

    private var todayOverflowMenu: some View {
        Menu {
            if viewModel.isTaskLedMode {
                Menu {
                    Picker("Schedule views", selection: $taskLedViewModeRaw) {
                        ForEach(TodayDisplayPreferences.TaskLedViewMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.icon)
                                .tag(mode.rawValue)
                        }
                    }
                } label: {
                    Label("Views", systemImage: "square.grid.2x2")
                }

                Button {
                    showSettingsSheet = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } else {
                Button("Choose TimeMap…") {
                    showFormulaPickerSheet = true
                }
                Button {
                    viewModel.createNewUserAlgorithmFromRoutineTemplate()
                } label: {
                    Label("New schedule", systemImage: "plus.square")
                }
                Button {
                    viewModel.restartFormulaDay()
                } label: {
                    Label("Reset schedule", systemImage: "arrow.counterclockwise")
                }
                .disabled(viewModel.isFormulaRunLive)
                Button(role: .destructive) {
                    viewModel.clearSchedule()
                } label: {
                    Label("Clear the schedule", systemImage: "calendar.badge.minus")
                }
                .disabled(!viewModel.canClearFormulaSchedule)
                Toggle(isOn: $pullsTasksFromExecutionPool) {
                    Label("Auto-fill blocks from To-do list", systemImage: "checklist")
                }
                Toggle(isOn: $scheduleShowsPagePlaybackControl) {
                    Label("Show play/pause on page", systemImage: "playpause.fill")
                }

                Button {
                    showSettingsSheet = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CueInColors.textPrimary)
        }
        .accessibilityLabel("Menu")
    }

    private func presentScheduleStart() {
        if viewModel.isFormulaRunStopped {
            viewModel.startFormulaDay()
        } else {
            let anchor = Date()
            scheduleStartRunAnchor = anchor
            draftScheduleEnd = viewModel.defaultScheduleTargetEnd
            showScheduleStartSheet = true
        }
    }

    private func toggleSchedulePlayback() {
        if viewModel.isFormulaSchedulePaused {
            viewModel.resumeFormulaScheduleAfterPause()
        } else if viewModel.isFormulaRunStopped {
            viewModel.startFormulaDay()
        } else if viewModel.isFormulaRunLive {
            viewModel.pauseFormulaSchedule()
        }
    }

    private func scrollToCurrentBlock(using proxy: ScrollViewProxy) {
        guard viewModel.isFormulaRunLive || viewModel.isTimelessRunLive else { return }
        guard let currentID = viewModel.currentBlockID else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.easeInOut(duration: 0.45)) {
                proxy.scrollTo(currentID, anchor: .center)
            }
        }
    }

    private func excludedPlannerTaskIDs(for blockID: UUID) -> Set<UUID> {
        Set((viewModel.blocks.first { $0.id == blockID }?.tasks ?? []).compactMap(\.plannerTaskItemID))
    }
}

// MARK: - To-do chrome sort (circle glass, matches ⋯ control)

private struct TodayTodoChromeSortMenu: View {
    let store: TasksStore
    let tasksToSort: [TaskItem]

    private var listKey: String { "today:todo" }

    var body: some View {
        Menu {
            Section {
                Button("By priority", systemImage: "line.3.horizontal.decrease") {
                    applyPrioritySort()
                }
            }
            Section("Order") {
                Button("Title A → Z", systemImage: "textformat.abc") {
                    applyTitleSort(ascending: true)
                }
                Button("Title Z → A", systemImage: "textformat.abc") {
                    applyTitleSort(ascending: false)
                }
                Button("Planned time · longest first", systemImage: "clock") {
                    applyPlannedSort(longestFirst: true)
                }
                Button("Planned time · shortest first", systemImage: "clock") {
                    applyPlannedSort(longestFirst: false)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CueInColors.textPrimary)
        }
        .accessibilityLabel("Sort to-do list")
    }

    private func syncTimeline() {
        TodayViewModel.shared.syncExecutionTimelineAfterExternalTaskEdit()
    }

    private func applyPrioritySort() {
        store.clearTaskListOrder(listKey: listKey)
        syncTimeline()
    }

    private func applyTitleSort(ascending: Bool) {
        let sorted = tasksToSort.sorted { a, b in
            let cmp = a.title.localizedStandardCompare(b.title)
            if cmp == .orderedSame { return a.createdAt < b.createdAt }
            return ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
        }
        store.setTaskOrder(listKey: listKey, orderedIDs: sorted.map(\.id))
        syncTimeline()
    }

    private func applyPlannedSort(longestFirst: Bool) {
        let sorted = tasksToSort.sorted { a, b in
            if a.plannedMinutes != b.plannedMinutes {
                return longestFirst ? (a.plannedMinutes > b.plannedMinutes) : (a.plannedMinutes < b.plannedMinutes)
            }
            let t = a.title.localizedStandardCompare(b.title)
            if t == .orderedSame { return a.createdAt < b.createdAt }
            return t == .orderedAscending
        }
        store.setTaskOrder(listKey: listKey, orderedIDs: sorted.map(\.id))
        syncTimeline()
    }
}

// MARK: - To-do chrome summary (thin pill, matches menu height)

private struct TodayTodoChromeSummaryBarPill: View {
    let metric: TodayDisplayPreferences.TodoChromeSummaryMetric
    let openCount: Int
    let completedCount: Int
    let totalCount: Int
    let plannedMinutesOpen: Int

    private var line: String {
        switch metric {
        case .plannedTime:
            return TodayDisplayPreferences.formatTodoPlannedMinutesLine(plannedMinutesOpen)
        case .openCount:
            return "\(openCount)"
        case .completedCount:
            return "\(completedCount)"
        case .totalCount:
            return "\(totalCount)"
        case .openAndPlanned:
            let t = TodayDisplayPreferences.formatTodoPlannedMinutesLine(plannedMinutesOpen)
            return "\(openCount) · \(t)"
        }
    }

    private var accessibilitySummary: String {
        switch metric {
        case .plannedTime:
            return "Planned time on open tasks, \(TodayDisplayPreferences.formatTodoPlannedMinutesLine(plannedMinutesOpen))"
        case .openCount:
            return "\(openCount) open tasks"
        case .completedCount:
            return "\(completedCount) completed tasks"
        case .totalCount:
            return "\(totalCount) tasks total"
        case .openAndPlanned:
            return "\(openCount) open tasks, planned \(TodayDisplayPreferences.formatTodoPlannedMinutesLine(plannedMinutesOpen))"
        }
    }

    var body: some View {
        Text(line)
            .font(.system(size: 13, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(CueInColors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(white: 0.15))
            .clipShape(Capsule(style: .continuous))
            .accessibilityLabel(accessibilitySummary)
    }
}

private enum TaskTimelineEditorRoute: Identifiable {
    /// Full `TaskDetailSheet` — same editor as the Tasks tab.
    case storeTask(UUID)
    /// Timeline-only row (no `TaskItem` link); legacy compact editor.
    case executionOnly(ExecutionTaskEditRequest)

    var id: String {
        switch self {
        case .storeTask(let taskItemID):
            return "store-\(taskItemID.uuidString)"
        case .executionOnly(let request):
            return request.id
        }
    }
}

private struct IdentifiedBlockID: Identifiable, Hashable {
    let id: UUID
}

/// Hold a `DayBlock` copy when opening the editor so a schedule rematerialize (new UUIDs)
/// or async update cannot drop the row from `viewModel.blocks` and dismiss a blank sheet.
private struct BlockEditSheetItem: Identifiable {
    let id: UUID
    let blockID: UUID
    var block: DayBlock

    init(block: DayBlock) {
        self.id = UUID()
        self.blockID = block.id
        self.block = block
    }
}

private struct ExecutionTaskEditRequest: Identifiable {
    let dayID: Date
    let task: ExecutionTaskCard

    var id: String {
        "\(Int(dayID.timeIntervalSince1970))-\(task.id.uuidString)"
    }
}

#Preview {
    ZStack {
        CueInColors.background.ignoresSafeArea()
        TodayView()
    }
    .cueInPreferredColorScheme()
}
