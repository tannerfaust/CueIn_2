import SwiftUI

// MARK: - TodayView
/// The Today tab — Day Engine. Content extends behind the tab bar.

struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = TodayViewModel.shared
    @State private var tasksStore = TasksStore.shared
    @State private var showFormulaPickerSheet = false
    @State private var showScheduleMakerSheet = false
    @State private var showSettingsSheet = false
    @State private var showScheduleStartSheet = false
    @State private var draftScheduleEnd = Date().addingTimeInterval(8 * 3600)
    @State private var timelineEditorRoute: TaskTimelineEditorRoute?
    @State private var draggedScheduleBlockID: UUID?
    @State private var blockTitleEdit: BlockEditSheetItem?
    @State private var blockAddTask: IdentifiedBlockID?
    @State private var blockDeleteConfirm: IdentifiedBlockID?
    @State private var isJiggleRearrangeMode = false
    @AppStorage(TodayDisplayPreferences.showScheduleStartTime) private var showScheduleStartTime = true
    @AppStorage(TodayDisplayPreferences.showScheduleDuration) private var showScheduleDuration = false
    @AppStorage(TodayDisplayPreferences.showScheduleTimeRange) private var showScheduleTimeRange = false
    @AppStorage(TodayDisplayPreferences.timelineHourHeight)  private var timelineHourHeight = TodayDisplayPreferences.timelineHourHeightDefault
    @AppStorage(TodayDisplayPreferences.timelineLayoutMode)  private var timelineLayoutModeRaw = TodayDisplayPreferences.TimelineLayoutMode.vertical.rawValue
    @AppStorage(TodayDisplayPreferences.taskLedViewMode) private var taskLedViewModeRaw = TodayDisplayPreferences.TaskLedViewMode.timeline.rawValue
    @AppStorage(TodayDisplayPreferences.todoViewShowInfoBlock) private var todoViewShowInfoBlock = true
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

    private var timelineLayoutMode: TodayDisplayPreferences.TimelineLayoutMode {
        TodayDisplayPreferences.TimelineLayoutMode(rawValue: timelineLayoutModeRaw) ?? .vertical
    }

    private var taskLedViewMode: TodayDisplayPreferences.TaskLedViewMode {
        TodayDisplayPreferences.TaskLedViewMode(rawValue: taskLedViewModeRaw) ?? .timeline
    }

    private var scheduleDesign: TodayDisplayPreferences.ScheduleDesign {
        TodayDisplayPreferences.migratedScheduleDesign(from: scheduleDesignRaw)
    }

    private var runningLineStyle: TodayDisplayPreferences.RunningLineStyle {
        TodayDisplayPreferences.migratedRunningLineStyle(from: runningLineStyleRaw)
    }

    /// “Compress remaining” pause: neutral running-line fill; “End later” keeps block colors and frozen progress.
    private var runningLineGreyFillWhilePausedReplan: Bool {
        viewModel.isFormulaSchedulePaused
            && TodayDisplayPreferences.migratedSchedulePauseBehavior(from: schedulePauseBehaviorRaw) == .compressRemaining
    }

    private var scheduleBlockTimerStyle: TodayDisplayPreferences.ScheduleBlockTimerStyle {
        TodayDisplayPreferences.migratedScheduleBlockTimerStyle(from: scheduleBlockTimerStyleRaw)
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
                                            accentColors: viewModel.runningLineAccentColors,
                                            blockSegments: viewModel.runningLineBlockSegments,
                                            greyFillWhilePausedReplan: runningLineGreyFillWhilePausedReplan,
                                            isStopped: viewModel.isFormulaRunStopped
                                        )
                                    } else if !viewModel.shouldShowScheduleEmptyCallout,
                                        viewModel.isFormulaPreviewing || viewModel.isFormulaRunStopped {
                                        Text(viewModel.headerStatusLine)
                                            .font(CueInTypography.caption)
                                            .foregroundStyle(CueInColors.textTertiary)
                                            .padding(.horizontal, CueInSpacing.screenHorizontal)
                                            .padding(.top, CueInSpacing.xs)
                                    }

                                    if viewModel.isFormulaPreviewing, viewModel.hasFormulaTemplate {
                                        Text("Start locks times and begins the first block.")
                                            .font(CueInTypography.caption)
                                            .foregroundStyle(CueInColors.textTertiary)
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
            .background(CueInColors.background)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                TodayTopChromeBar(
                    title: (viewModel.isTaskLedMode && taskLedViewMode == .todo) ? "To-do" : "Today",
                    prominentTitle: viewModel.isTaskLedMode && taskLedViewMode == .todo,
                    showsStart: viewModel.hasFormulaTemplate && viewModel.isFormulaPreviewing,
                    onStart: {
                        isJiggleRearrangeMode = false
                        presentScheduleStart()
                    },
                    showsSchedulePlayback: scheduleShowsPagePlaybackControl && viewModel.hasFormulaRunStarted,
                    schedulePlaybackSystemImage: (viewModel.isFormulaRunStopped || viewModel.isFormulaSchedulePaused) ? "play.fill" : "pause.fill",
                    schedulePlaybackAccessibilityLabel: (viewModel.isFormulaRunStopped || viewModel.isFormulaSchedulePaused) ? "Resume schedule" : "Pause schedule",
                    onSchedulePlayback: toggleSchedulePlayback,
                    showsRearrangeDone: isJiggleRearrangeMode,
                    onRearrangeDone: { isJiggleRearrangeMode = false },
                    scheduleLiveMenu: { EmptyView() },
                    trailing: { todayOverflowMenu }
                )
            }
        }
        .tint(CueInColors.textPrimary)
        .sheet(isPresented: $showFormulaPickerSheet) {
                FormulaPickerSheet(
                    formulas: viewModel.availableFormulas,
                    selectedFormulaID: viewModel.selectedFormulaID,
                    onSelect: { formulaID in
                        viewModel.selectFormula(formulaID)
                        showFormulaPickerSheet = false
                    },
                    onCreate: {
                        showFormulaPickerSheet = false
                        showScheduleMakerSheet = true
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
                onDismiss: { showSettingsSheet = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(isPresented: $showScheduleStartSheet) {
            let startPreview = viewModel.scheduleStartPreview(targetEnd: draftScheduleEnd)
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
            .presentationDetents(startPreview.preflightIssues.isEmpty ? [.medium] : [.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
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
        .sheet(isPresented: $showScheduleMakerSheet) {
            ScheduleMakerSheet(
                availableScopes: viewModel.scheduleMakerTaskScopes,
                onSave: { formula in
                    viewModel.saveCreatedFormula(formula)
                    showScheduleMakerSheet = false
                },
                onDismiss: { showScheduleMakerSheet = false }
            )
            .presentationDetents([.large])
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
            AddTaskToBlockSheet(
                onAdd: { text in
                    viewModel.addTemplateTaskToFormulaBlock(blockID: box.id, title: text)
                    blockAddTask = nil
                },
                onCancel: { blockAddTask = nil }
            )
            .presentationDetents([.medium])
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

    private var todayOverflowMenu: some View {
        Menu {
            if viewModel.isTaskLedMode {
                Picker("View", selection: $taskLedViewModeRaw) {
                    ForEach(TodayDisplayPreferences.TaskLedViewMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.icon)
                            .tag(mode.rawValue)
                    }
                }

                if taskLedViewMode == .todo {
                    Menu {
                        Toggle(isOn: $todoViewShowInfoBlock) {
                            Label("Show summary info", systemImage: "rectangle.and.text.magnifyingglass")
                        }
                    } label: {
                        Label("To-do view settings", systemImage: "checklist")
                    }
                }

                Button {
                    viewModel.setDayEngineMode(.formulaBased)
                } label: {
                    Label("Switch to Schedule", systemImage: "list.bullet.rectangle")
                }
            } else {
                Button {
                    viewModel.setDayEngineMode(.taskLed)
                } label: {
                    Label("Switch to Timeline", systemImage: "calendar.day.timeline.left")
                }
            }

            if viewModel.isFormulaMode {
                Button("Choose schedule…") {
                    showFormulaPickerSheet = true
                }
                Button {
                    showScheduleMakerSheet = true
                } label: {
                    Label("Make schedule…", systemImage: "plus.square")
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
                    Label("Use execution pool for tasks", systemImage: "tray.full")
                }
                Toggle(isOn: $scheduleShowsPagePlaybackControl) {
                    Label("Show play/pause on page", systemImage: "playpause.fill")
                }
            }

            Button {
                showSettingsSheet = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        } label: {
            TodayChromeMenuGlyph()
        }
        .accessibilityLabel("Menu")
    }

    private func presentScheduleStart() {
        if viewModel.isFormulaRunStopped {
            viewModel.startFormulaDay()
        } else {
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
    .preferredColorScheme(.dark)
}
