import SwiftUI

// MARK: - TimeblockFocusModeView

/// Full-screen focus on time blocks: swipe between blocks, live timer on the active block,
/// and schedule-style preview for upcoming blocks with a start-now action.
struct TimeblockFocusModeView: View {
    let initialBlockID: UUID
    var frozenProgressDate: Date? = nil
    var showsFinishControl: Bool = true
    let onDismiss: () -> Void

    @Bindable private var viewModel = TodayViewModel.shared
    @Bindable private var tasksStore = TasksStore.shared
    @Bindable private var soundStore = FocusSoundscapeStore.shared
    @AppStorage(TodayDisplayPreferences.timeblockFocusShowBlockIcon) private var showBlockIcon = true
    @AppStorage(TodayDisplayPreferences.timeblockFocusShowNowLabel) private var showNowLabel = true
    @AppStorage(TodayDisplayPreferences.timeblockFocusShowTimeRange) private var showTimeRange = true
    @AppStorage(TodayDisplayPreferences.timeblockFocusShowProgressBar) private var showProgressBar = true
    @AppStorage(TodayDisplayPreferences.timeblockFocusShowRemainingLine) private var showRemainingLine = true
    @AppStorage(TodayDisplayPreferences.timeblockFocusShowTaskCount) private var showTaskCount = true
    @AppStorage(TodayDisplayPreferences.timeblockFocusTimerShowsSeconds) private var timerShowsSeconds = false

    @State private var focusedBlockID: UUID
    @State private var showSettingsSheet = false
    @State private var showAddTaskSheet = false
    @State private var showSoundscapeSheet = false
    @State private var startBlockPrompt: FormulaBlockStartPrompt?
    @Environment(\.dismiss) private var dismiss

    init(
        initialBlockID: UUID,
        frozenProgressDate: Date? = nil,
        showsFinishControl: Bool = true,
        onDismiss: @escaping () -> Void
    ) {
        self.initialBlockID = initialBlockID
        self.frozenProgressDate = frozenProgressDate
        self.showsFinishControl = showsFinishControl
        self.onDismiss = onDismiss
        _focusedBlockID = State(initialValue: initialBlockID)
    }

    private var focusBlocks: [DayBlock] {
        viewModel.blocks.filter { $0.state != .skipped }
    }

    private var focusedBlock: DayBlock? {
        viewModel.blocks.first { $0.id == focusedBlockID }
    }

    private var focusedBlockAccent: Color {
        guard let focusedBlock else { return CueInColors.accentFocus }
        return accent(for: focusedBlock)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundLayer

                if focusBlocks.isEmpty {
                    missingBlockState
                } else {
                    TabView(selection: $focusedBlockID) {
                        ForEach(focusBlocks) { block in
                            focusPage(for: block)
                                .tag(block.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: focusBlocks.count > 1 ? .automatic : .never))
                }
            }
            .navigationTitle(navigationTitle)
            .cueInNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        close()
                    }
                    .foregroundStyle(CueInColors.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    focusOverflowMenu
                }
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            NavigationStack {
                ScrollView(.vertical, showsIndicators: false) {
                    TimeblockFocusModeSettingsSection()
                        .padding(.horizontal, CueInSpacing.screenHorizontal)
                        .padding(.vertical, CueInSpacing.md)
                }
                .background(CueInColors.background)
                .navigationTitle("Focus settings")
                .cueInNavigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showSettingsSheet = false
                        }
                        .foregroundStyle(CueInColors.textPrimary)
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(isPresented: $showSoundscapeSheet) {
            FocusSoundscapeSheet(
                accent: focusedBlockAccent,
                onDismiss: { showSoundscapeSheet = false }
            )
        }
        .sheet(isPresented: $showAddTaskSheet) {
            ScheduleBlockAddTaskSheet(
                store: tasksStore,
                excludedTaskIDs: excludedPlannerTaskIDs,
                captureDefaultsToToday: true,
                onPickExisting: { item in
                    viewModel.linkPlannerTaskToFormulaBlock(blockID: focusedBlockID, item: item)
                    showAddTaskSheet = false
                },
                onQuickCaptureSaved: { item in
                    viewModel.linkPlannerTaskToFormulaBlock(blockID: focusedBlockID, item: item)
                    showAddTaskSheet = false
                },
                onQuickCaptureExpand: { draft in
                    tasksStore.addTask(draft)
                    viewModel.linkPlannerTaskToFormulaBlock(blockID: focusedBlockID, item: draft)
                    showAddTaskSheet = false
                },
                onDismiss: { showAddTaskSheet = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .onChange(of: focusBlocks.map(\.id)) { _, ids in
            guard !ids.contains(focusedBlockID), let fallback = ids.first else { return }
            focusedBlockID = fallback
        }
        .confirmationDialog(
            startBlockPrompt?.dialogTitle ?? "Start block",
            isPresented: Binding(
                get: { startBlockPrompt != nil },
                set: { isPresented in
                    if !isPresented { startBlockPrompt = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            if let prompt = startBlockPrompt {
                Button(prompt.finishPriorLabel) {
                    applyStartBlockChoice(prompt, strategy: .finishPriorAndStart)
                }
                Button(prompt.deferPriorLabel) {
                    applyStartBlockChoice(prompt, strategy: .startNowDeferActiveAfter)
                }
                Button("Cancel", role: .cancel) {
                    startBlockPrompt = nil
                }
            }
        } message: {
            if let prompt = startBlockPrompt {
                Text(prompt.message)
            }
        }
    }

    private var navigationTitle: String {
        guard let index = focusBlocks.firstIndex(where: { $0.id == focusedBlockID }) else {
            return "Focus"
        }
        if focusBlocks.count > 1 {
            return "Block \(index + 1) of \(focusBlocks.count)"
        }
        return "Focus"
    }

    private var excludedPlannerTaskIDs: Set<UUID> {
        Set((focusedBlock?.tasks ?? []).compactMap(\.plannerTaskItemID))
    }

    // MARK: - Menu

    private var focusOverflowMenu: some View {
        Menu {
            Button {
                showSettingsSheet = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            if showsFinishControl, focusedBlock?.state == .active {
                Button {
                    finishKeepingPending()
                } label: {
                    Label("Finish block", systemImage: "flag.checkered")
                }
                Button {
                    completeAllTasks()
                } label: {
                    Label("Finish & complete all tasks", systemImage: "checkmark.seal")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CueInColors.textPrimary)
        }
        .accessibilityLabel("Menu")
        .cueInMenuInteractionStability()
    }

    // MARK: - Pages

    @ViewBuilder
    private func focusPage(for block: DayBlock) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: CueInSpacing.xl) {
                switch block.state {
                case .active:
                    activeHeroCard(for: block)
                case .upcoming:
                    upcomingHeroCard(for: block)
                    if canStartBlockNow(block) {
                        startBlockNowButton(blockID: block.id, accent: accent(for: block))
                    }
                case .completed:
                    completedHeroCard(for: block)
                case .skipped:
                    skippedHeroCard(for: block)
                }
                tasksSection(for: block)
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)
            .padding(.top, CueInSpacing.md)
            .padding(.bottom, CueInSpacing.xxxl)
        }
    }

    // MARK: - Hero cards

    private func activeHeroCard(for block: DayBlock) -> some View {
        let blockAccent = accent(for: block)

        return VStack(alignment: .leading, spacing: CueInSpacing.lg) {
            HStack(alignment: .center, spacing: CueInSpacing.md) {
                if showBlockIcon {
                    blockIcon(for: block, accent: blockAccent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if showNowLabel {
                        Text("NOW")
                            .font(CueInTypography.micro)
                            .tracking(0.8)
                            .foregroundStyle(blockAccent)
                    }
                    Text(block.title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(CueInColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if viewModel.isFormulaSchedulePaused {
                Label("TimeMap paused — timer frozen", systemImage: "pause.circle.fill")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
            }

            TimelineView(.periodic(from: .now, by: timerShowsSeconds ? 1 : 30)) { timeline in
                let now = frozenProgressDate ?? timeline.date
                let remaining = Int(block.endTime.timeIntervalSince(now))
                let isOvertime = remaining <= 0
                let overtimeSeconds = max(-remaining, 0)
                let progress = focusProgress(block: block, at: now)

                VStack(alignment: .leading, spacing: CueInSpacing.md) {
                    HStack(alignment: .firstTextBaseline, spacing: CueInSpacing.sm) {
                        Text(timerLabel(remaining: remaining, showsSeconds: timerShowsSeconds))
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .foregroundStyle(isOvertime ? CueInColors.danger : CueInColors.textPrimary)
                            .monospacedDigit()

                        Spacer(minLength: 0)

                        if showTimeRange {
                            Text(block.timeRangeLabel)
                                .font(CueInTypography.caption)
                                .foregroundStyle(CueInColors.textTertiary)
                                .monospacedDigit()
                        }
                    }

                    if showRemainingLine {
                        if isOvertime {
                            Text("\(overtimeCaption(seconds: overtimeSeconds)) overtime")
                                .font(CueInTypography.captionMedium)
                                .foregroundStyle(CueInColors.danger)
                        } else {
                            Text(remainingCaption(seconds: remaining))
                                .font(CueInTypography.captionMedium)
                                .foregroundStyle(CueInColors.textSecondary)
                        }
                    }

                    if showProgressBar {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(CueInColors.surfaceTertiary.opacity(0.65))
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                (isOvertime ? CueInColors.danger : blockAccent).opacity(0.95),
                                                (isOvertime ? CueInColors.danger : blockAccent).opacity(0.55),
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(6, geo.size.width * progress))
                            }
                        }
                        .frame(height: 8)
                    }
                }
            }

            FocusSoundscapeInlineControl(
                store: soundStore,
                accent: blockAccent,
                onOpenSounds: { showSoundscapeSheet = true }
            )
        }
        .padding(CueInSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(CueInColors.scheduleRunningBlockWash(accent: blockAccent))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(blockAccent.opacity(0.22), lineWidth: 0.75)
        }
    }

    private func upcomingHeroCard(for block: DayBlock) -> some View {
        let blockAccent = accent(for: block)

        return VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack(alignment: .top, spacing: CueInSpacing.sm) {
                if showBlockIcon {
                    blockIcon(for: block, accent: blockAccent)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(block.title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(CueInColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    upcomingMetaLine(for: block)
                }

                Spacer(minLength: 0)

                Text("\(block.durationMinutes)m")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(CueInColors.textSecondary)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CueInColors.surfaceTertiary.opacity(0.72))
                    )
                    .accessibilityLabel("Planned duration \(block.durationMinutes) minutes")
            }

            if showTimeRange {
                Text(block.timeRangeLabel)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
                    .monospacedDigit()
            }

            if block.pinsToClock || block.isAnchorBlock {
                Label("Pinned to clock", systemImage: "pin.fill")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
            }
        }
        .padding(CueInSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(CueInColors.surfacePrimary.opacity(0.4))
        )
        .glassSurface(cornerRadius: 22)
    }

    private func completedHeroCard(for block: DayBlock) -> some View {
        let blockAccent = accent(for: block)

        return VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            Label("Completed", systemImage: "checkmark.circle.fill")
                .font(CueInTypography.captionMedium)
                .foregroundStyle(CueInColors.textSecondary)

            HStack(alignment: .top, spacing: CueInSpacing.sm) {
                if showBlockIcon {
                    blockIcon(for: block, accent: blockAccent.opacity(0.7))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(block.title)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(CueInColors.textSecondary)
                    if showTimeRange {
                        Text(block.timeRangeLabel)
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textTertiary)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(CueInSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CueInColors.surfacePrimary.opacity(0.22))
        )
        .glassSurface(cornerRadius: 18)
        .opacity(0.92)
    }

    private func skippedHeroCard(for block: DayBlock) -> some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            Label("Skipped", systemImage: "forward.fill")
                .font(CueInTypography.captionMedium)
                .foregroundStyle(CueInColors.textTertiary)
            Text(block.title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(CueInColors.textTertiary)
        }
        .padding(CueInSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CueInColors.surfacePrimary.opacity(0.18))
        )
        .glassSurface(cornerRadius: 18)
    }

    private func startBlockNowButton(blockID: UUID, accent: Color) -> some View {
        Button {
            requestStartBlockNow(blockID: blockID)
        } label: {
            Text("Start this time block now")
                .font(CueInTypography.bodyMedium)
                .fontWeight(.semibold)
                .foregroundStyle(CueInColors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, CueInSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(accent.opacity(0.22))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accent.opacity(0.45), lineWidth: 0.75)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start this time block now")
    }

    @ViewBuilder
    private func upcomingMetaLine(for block: DayBlock) -> some View {
        let parts = upcomingMetaParts(for: block)
        if parts.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Text("·")
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textTertiary.opacity(0.6))
                    }
                    Text(item)
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textSecondary)
                }
            }
        }
    }

    private func upcomingMetaParts(for block: DayBlock) -> [String] {
        var parts: [String] = []
        if block.isRepeatable, block.taskSource == .templateTasks {
            parts.append("Routine")
        }
        switch block.taskSource {
        case .executionFill:
            parts.append("Auto-fill")
        case .templateTasks where !block.tasks.isEmpty:
            parts.append("\(block.tasks.count) tasks")
        case .noTasks, .templateTasks:
            break
        }
        return parts
    }

    private func blockIcon(for block: DayBlock, accent: Color) -> some View {
        Image(systemName: block.resolvedTimelineGlyph)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(0.14))
            )
    }

    // MARK: - Tasks

    private func tasksSection(for block: DayBlock) -> some View {
        let blockAccent = accent(for: block)
        let canAdd = canAddTasks(to: block)

        return VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack {
                Text("Tasks")
                    .font(CueInTypography.headline)
                    .foregroundStyle(CueInColors.textPrimary)
                Spacer(minLength: 0)
                if showTaskCount, !block.tasks.isEmpty {
                    Text("\(block.completedTaskCount)/\(block.tasks.count)")
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(CueInColors.textSecondary)
                        .monospacedDigit()
                }
            }

            VStack(spacing: 0) {
                if block.tasks.isEmpty {
                    VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                        Text("No tasks yet")
                            .font(CueInTypography.bodyMedium)
                            .foregroundStyle(CueInColors.textSecondary)
                        Text(taskSourceHint(block))
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(CueInSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(block.tasks) { task in
                        TaskRowView(task: task, blockAccent: blockAccent) {
                            viewModel.toggleTask(blockID: block.id, taskID: task.id)
                        }
                        if task.id != block.tasks.last?.id {
                            Rectangle()
                                .fill(CueInColors.divider.opacity(0.55))
                                .frame(height: 0.5)
                                .padding(.leading, 40)
                        }
                    }
                    .padding(.horizontal, CueInSpacing.md)
                    .padding(.vertical, CueInSpacing.sm)
                }

                if canAdd {
                    Rectangle()
                        .fill(CueInColors.divider.opacity(0.45))
                        .frame(height: 0.5)

                    addTaskButton(blockID: block.id, accent: blockAccent)
                        .padding(.horizontal, CueInSpacing.md)
                        .padding(.vertical, CueInSpacing.sm)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                    .fill(CueInColors.surfaceSecondary.opacity(0.55))
            )
        }
    }

    private func addTaskButton(blockID: UUID, accent: Color) -> some View {
        Button {
            focusedBlockID = blockID
            showAddTaskSheet = true
        } label: {
            HStack(spacing: CueInSpacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)
                Text("Add task")
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add task to this block")
    }

    private var backgroundLayer: some View {
        ZStack {
            CueInColors.background.ignoresSafeArea()
            if focusedBlock != nil {
                RadialGradient(
                    colors: [
                        focusedBlockAccent.opacity(0.16),
                        focusedBlockAccent.opacity(0.04),
                        Color.clear,
                    ],
                    center: .top,
                    startRadius: 40,
                    endRadius: 420
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.25), value: focusedBlockID)
            }
        }
    }

    private var missingBlockState: some View {
        VStack(spacing: CueInSpacing.md) {
            Text("No time blocks to show")
                .font(CueInTypography.title)
                .foregroundStyle(CueInColors.textPrimary)
            Button("Close", action: close)
                .font(CueInTypography.bodyMedium)
        }
        .padding(CueInSpacing.xl)
    }

    // MARK: - Actions

    private func close() {
        onDismiss()
        dismiss()
    }

    private func finishKeepingPending() {
        viewModel.finishBlockKeepingPending(blockID: focusedBlockID)
        close()
    }

    private func completeAllTasks() {
        viewModel.completeBlock(blockID: focusedBlockID)
        close()
    }

    private func accent(for block: DayBlock) -> Color {
        CueInColors.resolvedTimelineAccent(blockType: block.type, hex: block.timelineAccentHex)
    }

    private func canAddTasks(to block: DayBlock) -> Bool {
        guard viewModel.canUseBlockContextMenu(blockID: block.id) else { return false }
        return block.state == .active || block.state == .upcoming
    }

    private func canStartBlockNow(_ block: DayBlock) -> Bool {
        viewModel.canStartFormulaBlockNow(blockID: block.id)
    }

    private func requestStartBlockNow(blockID: UUID) {
        if let prompt = viewModel.formulaBlockStartPrompt(for: blockID) {
            startBlockPrompt = prompt
            return
        }
        viewModel.applyFormulaBlockStart(blockID: blockID, strategy: .finishPriorAndStart)
        focusedBlockID = blockID
    }

    private func applyStartBlockChoice(_ prompt: FormulaBlockStartPrompt, strategy: FormulaBlockStartStrategy) {
        viewModel.applyFormulaBlockStart(blockID: prompt.targetBlockID, strategy: strategy)
        startBlockPrompt = nil
        focusedBlockID = prompt.targetBlockID
    }

    // MARK: - Formatting

    private func focusProgress(block: DayBlock, at date: Date) -> CGFloat {
        let total = max(block.endTime.timeIntervalSince(block.startTime), 1)
        let elapsed = date.timeIntervalSince(block.startTime)
        return CGFloat(min(max(elapsed / total, 0), 1))
    }

    private func timerLabel(remaining: Int, showsSeconds: Bool) -> String {
        if remaining > 0 {
            if showsSeconds {
                return digitalDuration(totalSeconds: remaining)
            }
            let minutes = max(Int(ceil(Double(remaining) / 60.0)), 1)
            return "\(minutes)m"
        }
        let overtime = -remaining
        if showsSeconds {
            return "-\(digitalDuration(totalSeconds: overtime))"
        }
        let minutes = max(Int(ceil(Double(overtime) / 60.0)), 1)
        return "-\(minutes)m"
    }

    private func digitalDuration(totalSeconds: Int) -> String {
        let safe = max(totalSeconds, 0)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let seconds = safe % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func remainingCaption(seconds: Int) -> String {
        if seconds <= 0 { return "Wrapping up" }
        if timerShowsSeconds {
            return "\(digitalDuration(totalSeconds: seconds)) left in this block"
        }
        let minutes = max(Int(ceil(Double(seconds) / 60.0)), 1)
        return minutes == 1 ? "1 minute left in this block" : "\(minutes) minutes left in this block"
    }

    private func overtimeCaption(seconds: Int) -> String {
        if timerShowsSeconds {
            return digitalDuration(totalSeconds: seconds)
        }
        let minutes = max(Int(ceil(Double(seconds) / 60.0)), 1)
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    private func taskSourceHint(_ block: DayBlock) -> String {
        switch block.taskSource {
        case .noTasks:
            return "Tap Add task below, or turn on To-do auto-fill for fill blocks."
        case .executionFill:
            return "Tasks from your To-do list appear here when auto-fill runs. You can still add your own."
        case .templateTasks:
            return "Add tasks with the button below."
        }
    }
}

#Preview {
    TimeblockFocusModeView(initialBlockID: UUID(), onDismiss: {})
        .cueInPreferredColorScheme()
}
