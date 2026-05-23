import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

// MARK: - SavePresetBannerKind

private enum SavePresetBannerKind: Equatable {
    case success
    case failure
}

// MARK: - ScheduleBlockEditorForm

struct ScheduleBlockEditorForm: View {
    struct LiveCountdownContext: Equatable {
        let startTime: Date
        let endTime: Date
    }

    @Binding var block: ScheduleBlockDraft
    let availableScopes: ScheduleMakerTaskScopes
    var allowsPoolFillSource: Bool = true
    var showsAnchorNotice: Bool = false
    var allowsFixedClockEdit: Bool = true
    var showsPresetLibrary: Bool = true
    /// New tasks from the full task sheet go to Today when editing a live block; Inbox when building a formula template.
    var createdTasksGoToToday: Bool = false
    /// When set, shows a bottom control to persist the block as a user preset (see ``FormulaLibraryService``). Return `true` when data was written.
    var onSavePreset: (() -> Bool)? = nil
    /// When set, the planned duration card can render a live, animated countdown reel for active blocks.
    var liveCountdownContext: LiveCountdownContext? = nil
    /// Called when the duration wheel confirms with Done.
    var onDurationCommit: (() -> Void)? = nil
    /// When false, duration override is blocked (for pinned timeline-anchor tasks).
    var allowsDurationOverride: Bool = true
    /// Optional warning shown when duration override is blocked.
    var durationOverrideWarning: String? = nil

    @State private var showPresetSheet = false
    @State private var savePresetBanner: SavePresetBannerKind?
    @State private var savePresetBannerDismiss: Task<Void, Never>?
    @State private var showAppearancePicker = false
    @State private var showDurationWheelSheet = false
    @State private var showTaskCreateSheet = false
    @State private var showAutofillPickOrderSheet = false
    @State private var showPinnedDatePicker = false
    @State private var durationPickerTotalSeconds: Int = 0
    @State private var durationAutoFollowsLive = true
    @State private var durationLiveSyncTask: Task<Void, Never>?

    struct TaskEditorItem: Identifiable {
        let id: UUID
    }

    @State private var editingTaskItem: TaskEditorItem? = nil
    @State private var activeStatusPopoverTaskID: UUID? = nil
    @State private var draggedTask: ScheduleTaskDraft? = nil

    @Bindable private var tasksStore = TasksStore.shared

    @State private var didRequestInitialFocus = false
    @FocusState private var titleFocused: Bool

    private enum PriorityTier: String, CaseIterable, Identifiable, Hashable {
        case balanced
        case highPriority
        case fixDuration

        var id: String { rawValue }

        var label: String {
            switch self {
            case .balanced: return "Balanced"
            case .highPriority: return "High priority"
            case .fixDuration: return "Fix duration"
            }
        }

        var icon: String {
            switch self {
            case .balanced: return "equal"
            case .highPriority: return "exclamationmark.circle"
            case .fixDuration: return "lock"
            }
        }

        var color: Color {
            switch self {
            case .balanced: return CueInColors.textSecondary
            case .highPriority: return CueInColors.accentFocus
            case .fixDuration: return CueInColors.textPrimary
            }
        }

        init(schedulingPriority: Int?, locksPlannedDuration: Bool) {
            if locksPlannedDuration {
                self = .fixDuration
                return
            }
            if let p = schedulingPriority, p >= 65 {
                self = .highPriority
                return
            }
            self = .balanced
        }

        func apply(to block: Binding<ScheduleBlockDraft>) {
            switch self {
            case .fixDuration:
                block.wrappedValue.locksPlannedDuration = true
                block.wrappedValue.schedulingPriority = nil
            case .balanced:
                block.wrappedValue.locksPlannedDuration = false
                block.wrappedValue.schedulingPriority = nil
            case .highPriority:
                block.wrappedValue.locksPlannedDuration = false
                block.wrappedValue.schedulingPriority = 75
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            if showsAnchorNotice {
                anchorBanner
            }

            topProperties

            titleField

            if block.pinsToClock {
                pinnedStartSection
            }

            if block.assignsTasks {
                linkedTasksSection
                autofillSection
            }

            libraryActionsSection
        }
        .onChange(of: block.pinsToClock) { _, pinned in
            if !pinned {
                block.fixedClockMinutesFromDayStart = nil
                block.fixedClockDate = nil
                showPinnedDatePicker = false
            } else if block.fixedClockMinutesFromDayStart == nil {
                let now = Date()
                let cal = Calendar.current
                let components = cal.dateComponents([.hour, .minute], from: now)
                block.fixedClockMinutesFromDayStart = max(0, min(24 * 60 - 1, (components.hour ?? 9) * 60 + (components.minute ?? 0)))
                block.fixedClockDate = cal.startOfDay(for: now)
            } else if block.fixedClockDate == nil {
                block.fixedClockDate = Calendar.current.startOfDay(for: Date())
            }
        }
        .task(id: block.id) {
            applyInitialTimelineGlyphSuggestionIfNeeded()
            applyCategoryAutoAssignment(to: block.title)
        }
        .onChange(of: block.title) { oldTitle, newTitle in
            applyTimelineGlyphSuggestionAfterTitleChange(from: oldTitle, to: newTitle)
            applyCategoryAutoAssignment(to: newTitle)
        }
        .onChange(of: block.id) { _, _ in
            savePresetBannerDismiss?.cancel()
            savePresetBannerDismiss = nil
            savePresetBanner = nil
        }
        .onDisappear {
            savePresetBannerDismiss?.cancel()
            savePresetBannerDismiss = nil
            durationLiveSyncTask?.cancel()
            durationLiveSyncTask = nil
        }
        .onAppear {
            resetDurationPickerFromBlock()
        }
        .onChange(of: block.durationMinutes) { _, _ in
            if showDurationWheelSheet { return }
            resetDurationPickerFromBlock()
        }
        .sheet(isPresented: $showPresetSheet) {
            BlockTemplateLibrarySheet(
                onPick: { template in
                    block.applyPreset(from: template)
                    showPresetSheet = false
                },
                onDismiss: { showPresetSheet = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(isPresented: $showAppearancePicker) {
            ScheduleBlockAppearancePickerSheet(block: $block)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(isPresented: $showDurationWheelSheet) {
            durationWheelSheet
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(isPresented: $showAutofillPickOrderSheet) {
            AutofillPickOrderPickerSheet(pickOrder: $block.autofillPickOrder)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(isPresented: $showTaskCreateSheet) {
            ScheduleBlockAddTaskSheet(
                store: tasksStore,
                excludedTaskIDs: Set(block.tasks.compactMap(\.plannerTaskItemID)),
                captureDefaultsToToday: createdTasksGoToToday,
                onPickExisting: { item in
                    attachCreatedPlannerTask(item)
                },
                onQuickCaptureSaved: { item in
                    attachCreatedPlannerTask(item)
                },
                onQuickCaptureExpand: { draft in
                    tasksStore.addTask(draft)
                    attachCreatedPlannerTask(draft)
                    showTaskCreateSheet = false
                },
                onDismiss: { showTaskCreateSheet = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(item: $editingTaskItem) { item in
            TaskDetailSheet(mode: .edit(item.id), store: tasksStore) {
                editingTaskItem = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .onAppear(perform: focusTitleOnce)
    }
}

// MARK: - Layout Views

private extension ScheduleBlockEditorForm {
    var anchorBanner: some View {
        Text("Timeline anchor — pool fill is off.")
            .font(CueInTypography.caption)
            .foregroundStyle(CueInColors.textSecondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cueInEditorGlassSurface(cornerRadius: 14)
    }

    var topProperties: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // 1. Duration Chip
                Button {
                    if allowsDurationOverride {
                        showDurationWheelSheet = true
                    } else {
                        CueInToastCenter.shared.showWarning(
                            icon: "pin.slash",
                            title: "Duration locked by pinned task",
                            message: durationOverrideWarning ?? "This block comes from a pinned task, so its duration is fixed by the task's clock window."
                        )
                    }
                } label: {
                    durationChipLabel
                }
                .buttonStyle(.plain)

                // 2. Flow Mode Chip
                Menu {
                    ForEach(BlockFlowMode.allCases) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                block.flowMode = mode
                            }
                        } label: {
                            Label(mode.label, systemImage: mode.editorIconName)
                        }
                    }
                } label: {
                    BlockEditorPropertyChip(
                        icon: block.flowMode.editorIconName,
                        title: block.flowMode.label,
                        tint: CueInColors.textSecondary
                    )
                }
                .buttonStyle(.plain)

                // 3. Priority Chip
                let selection = PriorityTier(
                    schedulingPriority: block.schedulingPriority,
                    locksPlannedDuration: block.locksPlannedDuration
                )
                Menu {
                    ForEach(PriorityTier.allCases) { tier in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                tier.apply(to: $block)
                            }
                        } label: {
                            Label(tier.label, systemImage: tier.icon)
                        }
                    }
                } label: {
                    BlockEditorPropertyChip(
                        icon: selection.icon,
                        title: selection.label,
                        tint: selection.color
                    )
                }
                .buttonStyle(.plain)

                // 4. Pin Clock / Pin Start Chip
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        block.pinsToClock.toggle()
                    }
                } label: {
                    BlockEditorPropertyChip(
                        icon: block.pinsToClock ? "pin.fill" : "pin",
                        title: block.pinsToClock ? "Pinned (\(pinnedDateShortLabel))" : "No pin",
                        tint: block.pinsToClock ? CueInColors.accentFixed : CueInColors.textSecondary
                    )
                }
                .buttonStyle(.plain)

                // 5. Task Source Chip
                Menu {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            block.assignsTasks = false
                            block.poolFillEnabled = false
                            block.tasks = []
                            block.deepWorkOnly = false
                        }
                    } label: {
                        Label("No tasks", systemImage: "circle.dashed")
                    }
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            block.assignsTasks = true
                        }
                    } label: {
                        Label("Tasks", systemImage: "checkmark.circle.fill")
                    }
                } label: {
                    BlockEditorPropertyChip(
                        icon: block.assignsTasks ? "checkmark.circle.fill" : "circle.dashed",
                        title: block.assignsTasks ? "Tasks" : "No tasks",
                        tint: block.assignsTasks ? CueInColors.textPrimary : CueInColors.textSecondary
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    var durationChipLabel: some View {
        HStack(spacing: 7) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(allowsDurationOverride ? CueInColors.textSecondary : CueInColors.warning)

            if let context = liveCountdownContext, durationAutoFollowsLive {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let remaining = liveCountdownSignedSeconds(context: context, now: timeline.date)
                    Text(liveCountdownDigitalLabel(signedSeconds: remaining))
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(remaining <= 0 ? CueInColors.danger : CueInColors.textPrimary)
                        .monospacedDigit()
                }
            } else {
                Text(durationDigitalLabel(totalSeconds: durationPickerTotalSeconds))
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
        .cueInEditorGlassCapsule()
    }

    var titleField: some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                showAppearancePicker = true
            } label: {
                let tintColor = CueInColors.resolvedTimelineAccent(blockType: block.timelineAccent, hex: block.timelineAccentHex)
                ZStack {
                    Circle()
                        .fill(tintColor.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Circle()
                        .strokeBorder(tintColor.opacity(0.24), lineWidth: 1.5)
                        .frame(width: 48, height: 48)
                    Image(systemName: block.resolvedTimelineGlyph)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tintColor)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pick color and icon")

            TextField("Block title", text: $block.title, axis: .vertical)
                .font(Font.system(size: 30, weight: .bold))
                .foregroundStyle(CueInColors.textPrimary)
                .tint(CueInColors.textPrimary)
                .focused($titleFocused)
                .lineLimit(1...3)
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    var pinnedStartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pinned Start")
                .font(CueInTypography.micro)
                .foregroundStyle(CueInColors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 4)

            pinnedStartCard
        }
    }

    var pinnedStartCard: some View {
        pinnedStartControls
            .padding(CueInSpacing.md)
            .cueInEditorGlassSurface(cornerRadius: 22)
    }

    var linkedTasksSection: some View {
        linkedTasksCard
    }

    var linkedTasksCard: some View {
        VStack(spacing: 0) {
            if block.tasks.isEmpty {
                Button {
                    showTaskCreateSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CueInColors.textTertiary)
                            .frame(width: 18)
                        Text("Link tasks...")
                            .font(CueInTypography.body)
                            .foregroundStyle(CueInColors.textTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, CueInSpacing.md)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 0) {
                    ForEach(block.tasks) { task in
                        if let index = block.tasks.firstIndex(where: { $0.id == task.id }) {
                            HStack(spacing: CueInSpacing.sm) {
                                // 1. Checkbox button with popover status picker
                                Button {
                                    let pid = ensurePersistentTask(for: index)
                                    activeStatusPopoverTaskID = pid
                                } label: {
                                    let isCompleted = taskIsCompleted(for: task)
                                    let status = taskStatus(for: task)
                                    CueInTaskStatusCheckbox(
                                        isCompleted: isCompleted,
                                        workflowStatus: isCompleted ? nil : status,
                                        diameter: 18
                                    )
                                    .frame(width: 24, height: 24, alignment: .center)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(taskIsCompleted(for: task) ? "Completed task status" : "Task status")
                                .accessibilityHint("Opens task status options")
                                .popover(isPresented: Binding(
                                    get: { activeStatusPopoverTaskID == task.plannerTaskItemID && task.plannerTaskItemID != nil },
                                    set: { if !$0 { activeStatusPopoverTaskID = nil } }
                                )) {
                                    if let pid = task.plannerTaskItemID {
                                        CueInTaskStatusPopoverContent(selection: taskStatus(for: task)) { newStatus in
                                            tasksStore.setTodayTodoTaskStatus(id: pid, status: newStatus)
                                            activeStatusPopoverTaskID = nil
                                        }
                                    }
                                }

                                // 2. Row title click to open task editor sheet
                                Button {
                                    let pid = ensurePersistentTask(for: index)
                                    editingTaskItem = TaskEditorItem(id: pid)
                                } label: {
                                    HStack {
                                        let isCompleted = taskIsCompleted(for: task)
                                        Text(displayTitle(for: task))
                                            .font(CueInTypography.body)
                                            .foregroundStyle(isCompleted ? CueInColors.textTertiary : CueInColors.textPrimary)
                                            .strikethrough(isCompleted, color: CueInColors.textTertiary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Spacer(minLength: CueInSpacing.sm)

                                // 3. Delete button
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                        block.tasks.removeAll { $0.id == task.id }
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(CueInColors.textTertiary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove from block")
                            }
                            .padding(.horizontal, CueInSpacing.md)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                            .onDrag {
                                self.draggedTask = task
                                return NSItemProvider(object: task.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: TaskDropDelegate(
                                item: task,
                                list: $block.tasks,
                                draggedItem: $draggedTask
                            ))

                            if index < block.tasks.count - 1 {
                                Divider()
                                    .background(CueInColors.divider.opacity(0.4))
                                    .padding(.leading, 46)
                            }
                        }
                    }

                    Divider()
                        .background(CueInColors.divider.opacity(0.4))

                    Button {
                        showTaskCreateSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(CueInColors.textTertiary)
                                .frame(width: 18)
                            Text("Add task...")
                                .font(CueInTypography.body)
                                .foregroundStyle(CueInColors.textTertiary)
                            Spacer()
                        }
                        .padding(.horizontal, CueInSpacing.md)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cueInEditorGlassSurface(cornerRadius: 22)
    }

    var autofillSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Autofill Tasks")
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Toggle("", isOn: $block.poolFillEnabled)
                    .labelsHidden()
                    .tint(CueInColors.accentFocus)
            }
            .padding(.horizontal, 4)

            if block.poolFillEnabled {
                autofillCard
            }
        }
    }

    var autofillCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Automatically pull tasks matching criteria:")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, CueInSpacing.md)
            .padding(.vertical, 12)

            Divider()
                .background(CueInColors.divider.opacity(0.4))

            poolScopeFilterRow(
                title: "Field",
                systemImage: "square.grid.2x2",
                value: $block.fillField,
                anyMenuTitle: "Any field",
                options: availableScopes.fields
            )

            Divider()
                .background(CueInColors.divider.opacity(0.4))
                .padding(.leading, 46)

            poolScopeFilterRow(
                title: "Project",
                systemImage: "folder",
                value: $block.fillProject,
                anyMenuTitle: "Any project",
                options: availableScopes.projects
            )

            Divider()
                .background(CueInColors.divider.opacity(0.4))

            Button {
                showAutofillPickOrderSheet = true
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "arrow.up.arrow.down")
                       .font(.system(size: 13, weight: .medium))
                       .foregroundStyle(CueInColors.textTertiary)
                       .frame(width: 18)

                    Text("Order by")
                        .font(CueInTypography.body)
                        .foregroundStyle(CueInColors.textSecondary)

                    Spacer(minLength: CueInSpacing.md)

                    HStack(spacing: 4) {
                        Text(block.autofillPickOrder.editorTitle)
                            .font(CueInTypography.body)
                            .foregroundStyle(CueInColors.textPrimary)
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CueInColors.textTertiary)
                    }
                }
                .padding(.horizontal, CueInSpacing.md)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            Divider()
                .background(CueInColors.divider.opacity(0.4))

            Toggle(isOn: $block.deepWorkOnly) {
                HStack(spacing: 12) {
                    Image(systemName: "flame")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CueInColors.textTertiary)
                        .frame(width: 18)
                    Text("Deep work only")
                        .font(CueInTypography.body)
                        .foregroundStyle(CueInColors.textSecondary)
                }
            }
            .tint(CueInColors.accentFocus)
            .padding(.horizontal, CueInSpacing.md)
            .padding(.vertical, 10)
        }
        .cueInEditorGlassSurface(cornerRadius: 22)
    }

    var libraryActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Templates")
                .font(CueInTypography.micro)
                .foregroundStyle(CueInColors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 4)

            libraryActionsCard
        }
    }

    @ViewBuilder
    var libraryActionsCard: some View {
        if showsPresetLibrary || onSavePreset != nil {
            VStack(spacing: 0) {
                if let banner = savePresetBanner {
                    savePresetBannerRow(banner)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if showsPresetLibrary {
                    Button {
                        showPresetSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.stack")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(CueInColors.textTertiary)
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Block templates library")
                                    .font(CueInTypography.body)
                                    .foregroundStyle(CueInColors.textPrimary)
                                Text("Reuse a saved block or sample templates")
                                    .font(CueInTypography.caption)
                                    .foregroundStyle(CueInColors.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CueInColors.textTertiary)
                        }
                        .padding(.horizontal, CueInSpacing.md)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }

                if showsPresetLibrary && onSavePreset != nil {
                    Divider()
                        .background(CueInColors.divider.opacity(0.4))
                        .padding(.leading, 46)
                }

                if onSavePreset != nil {
                    Button(action: runSavePreset) {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(CueInColors.textTertiary)
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Save current block to library")
                                    .font(CueInTypography.body)
                                    .foregroundStyle(CueInColors.textPrimary)
                                Text("Add this setup to your template shortcuts")
                                    .font(CueInTypography.caption)
                                    .foregroundStyle(CueInColors.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(CueInColors.textSecondary)
                        }
                        .padding(.horizontal, CueInSpacing.md)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canPersistBlockAsPreset)
                    .opacity(canPersistBlockAsPreset ? 1 : 0.44)
                }
            }
            .cueInEditorGlassSurface(cornerRadius: 22)
        }
    }
}

// MARK: - Logic & Subcomponents

private extension ScheduleBlockEditorForm {
    var canPersistBlockAsPreset: Bool {
        !block.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func attachCreatedPlannerTask(_ item: TaskItem) {
        block.tasks.append(
            ScheduleTaskDraft(
                title: item.title,
                isPrimary: false,
                plannerTaskItemID: item.id
            )
        )
    }

    @ViewBuilder
    func savePresetBannerRow(_ kind: SavePresetBannerKind) -> some View {
        switch kind {
        case .success:
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CueInColors.success)
                Text("Saved to library")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, CueInSpacing.md)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                CueInColors.success.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .accessibilityLabel("Preset saved")
        case .failure:
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CueInColors.danger.opacity(0.95))
                Text("Couldn’t save — try again")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
            }
            .padding(.horizontal, CueInSpacing.md)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                CueInColors.danger.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .accessibilityLabel("Save failed")
        }
    }

    func runSavePreset() {
        guard let save = onSavePreset, canPersistBlockAsPreset else { return }

        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).prepare()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        let ok = save()

        savePresetBannerDismiss?.cancel()
        savePresetBannerDismiss = nil

        if ok {
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                savePresetBanner = .success
            }
            savePresetBannerDismiss = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if !Task.isCancelled {
                    withAnimation(.easeOut(duration: 0.22)) {
                        savePresetBanner = nil
                    }
                }
                savePresetBannerDismiss = nil
            }
        } else {
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            #endif
            withAnimation(.easeOut(duration: 0.22)) {
                savePresetBanner = .failure
            }
            savePresetBannerDismiss = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_800_000_000)
                if !Task.isCancelled {
                    withAnimation(.easeOut(duration: 0.2)) {
                        savePresetBanner = nil
                    }
                }
                savePresetBannerDismiss = nil
            }
        }
    }

    func applyInitialTimelineGlyphSuggestionIfNeeded() {
        let trimmedGlyph = block.timelineGlyph?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmedGlyph.isEmpty else { return }
        block.timelineGlyph = ScheduleBlockTitleGlyphSuggester.suggestedSymbol(for: block.title)
    }

    func applyTimelineGlyphSuggestionAfterTitleChange(from oldTitle: String, to newTitle: String) {
        let trimmedGlyph = block.timelineGlyph?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let priorSuggestion = ScheduleBlockTitleGlyphSuggester.suggestedSymbol(for: oldTitle)
        let nextSuggestion = ScheduleBlockTitleGlyphSuggester.suggestedSymbol(for: newTitle)

        let wasAutoTracked: Bool
        if let prior = priorSuggestion {
            wasAutoTracked = (prior == trimmedGlyph)
        } else {
            wasAutoTracked = trimmedGlyph.isEmpty
        }

        guard trimmedGlyph.isEmpty || wasAutoTracked else { return }
        block.timelineGlyph = nextSuggestion
    }

    func applyCategoryAutoAssignment(to title: String) {
        guard !block.isCategoryManuallySet else { return }
        if title.localizedCaseInsensitiveContains("work") {
            block.category = "Work"
        } else {
            block.category = "Others"
        }
    }

    var pinnedStartControls: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            HStack(spacing: CueInSpacing.sm) {
                DatePicker(
                    "Start time",
                    selection: fixedStartBinding,
                    displayedComponents: [.hourAndMinute]
                )
                .labelsHidden()
                .environment(\.locale, Locale.autoupdatingCurrent)
                .padding(.horizontal, CueInSpacing.md)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    CueInColors.surfacePrimary.opacity(0.48),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                        showPinnedDatePicker.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CueInColors.accentFixed)
                        Text(pinnedDateShortLabel)
                            .font(CueInTypography.micro)
                            .monospacedDigit()
                    }
                    .foregroundStyle(CueInColors.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(
                        CueInColors.surfacePrimary.opacity(0.48),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pinned date")
            }

            if showPinnedDatePicker {
                DatePicker(
                    "Pinned date",
                    selection: fixedDateBinding,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(CueInColors.accentFixed)
                .padding(CueInSpacing.sm)
                .background(
                    CueInColors.surfacePrimary.opacity(0.48),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
        }
    }

    var fixedStartBinding: Binding<Date> {
        Binding(
            get: {
                let mins = block.fixedClockMinutesFromDayStart ?? 9 * 60
                let cal = Calendar.current
                let base = block.fixedClockDate.map { cal.startOfDay(for: $0) } ?? cal.startOfDay(for: Date())
                return cal.date(byAdding: .minute, value: mins, to: base) ?? base
            },
            set: { newDate in
                let cal = Calendar.current
                let base = cal.startOfDay(for: newDate)
                let mins = Int(newDate.timeIntervalSince(base) / 60)
                block.fixedClockMinutesFromDayStart = max(0, min(24 * 60 - 1, mins))
                block.fixedClockDate = base
            }
        )
    }

    var fixedDateBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.startOfDay(for: block.fixedClockDate ?? Date())
            },
            set: { newDate in
                block.fixedClockDate = Calendar.current.startOfDay(for: newDate)
            }
        )
    }

    var pinnedDateShortLabel: String {
        let date = block.fixedClockDate ?? Date()
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }

    func displayTitle(for task: ScheduleTaskDraft) -> String {
        if let pid = task.plannerTaskItemID,
           let item = tasksStore.tasks.first(where: { $0.id == pid }) {
            return item.title
        }
        let trimmed = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    func taskStatus(for draft: ScheduleTaskDraft) -> TaskStatus {
        if let pid = draft.plannerTaskItemID,
           let item = tasksStore.tasks.first(where: { $0.id == pid }) {
            return item.status
        }
        return .scheduled
    }

    func taskIsCompleted(for draft: ScheduleTaskDraft) -> Bool {
        if let pid = draft.plannerTaskItemID,
           let item = tasksStore.tasks.first(where: { $0.id == pid }) {
            return item.isCompleted
        }
        return false
    }

    func ensurePersistentTask(for index: Int) -> UUID {
        let taskDraft = block.tasks[index]
        if let pid = taskDraft.plannerTaskItemID,
           tasksStore.tasks.contains(where: { $0.id == pid }) {
            return pid
        }
        
        let newID = UUID()
        let scheduledDate = Calendar.current.startOfDay(for: Date())
        let newTask = TaskItem(
            id: newID,
            title: taskDraft.title,
            notes: "",
            scheduledDate: scheduledDate,
            status: .scheduled
        )
        tasksStore.addTask(newTask)
        block.tasks[index].plannerTaskItemID = newID
        return newID
    }

    var durationWheelSheet: some View {
        NavigationStack {
            VStack(spacing: CueInSpacing.sm) {
                HStack(spacing: 0) {
                    Picker("Hours", selection: durationHoursBinding) {
                        ForEach(0...16, id: \.self) { hour in
                            Text(hourRowTitle(hour)).tag(hour)
                        }
                    }
                    .cueInWheelPickerStyle()
                    .frame(maxWidth: .infinity)

                    Picker("Minutes", selection: durationMinutesComponentBinding) {
                        ForEach(0...59, id: \.self) { mins in
                            Text(minuteRowTitle(minutes: mins)).tag(mins)
                        }
                    }
                    .cueInWheelPickerStyle()
                    .frame(maxWidth: .infinity)

                    Picker("Seconds", selection: durationSecondsComponentBinding) {
                        ForEach(0...59, id: \.self) { secs in
                            Text(minuteRowTitle(minutes: secs)).tag(secs)
                        }
                    }
                    .cueInWheelPickerStyle()
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 180)
                .clipped()
            }
            .padding(.top, 8)
            .navigationTitle("Timer")
            .cueInNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        normalizeDurationPicker()
                        onDurationCommit?()
                        showDurationWheelSheet = false
                    }
                    .foregroundStyle(CueInColors.textPrimary)
                }
            }
            .onAppear {
                if let context = liveCountdownContext {
                    durationPickerTotalSeconds = liveRemainingSeconds(context: context, now: Date())
                    durationAutoFollowsLive = true
                    startDurationLiveSyncIfNeeded()
                } else {
                    resetDurationPickerFromBlock()
                    durationAutoFollowsLive = false
                }
            }
            .onDisappear {
                durationLiveSyncTask?.cancel()
                durationLiveSyncTask = nil
            }
        }
    }

    var durationHourComponent: Int {
        min(16, durationPickerTotalSeconds / 3600)
    }

    var durationMinuteComponent: Int {
        (durationPickerTotalSeconds % 3600) / 60
    }

    var durationSecondComponent: Int {
        durationPickerTotalSeconds % 60
    }

    var durationHoursBinding: Binding<Int> {
        Binding(
            get: { durationHourComponent },
            set: { newHour in
                durationAutoFollowsLive = false
                let cappedHour = min(16, max(0, newHour))
                durationPickerTotalSeconds = clampDurationTotalSeconds(
                    hours: cappedHour,
                    minutes: durationMinuteComponent,
                    seconds: durationSecondComponent
                )
                syncPickerToDraftMinutes()
            }
        )
    }

    var durationMinutesComponentBinding: Binding<Int> {
        Binding(
            get: {
                durationMinuteComponent
            },
            set: { newMins in
                durationAutoFollowsLive = false
                let h = durationHourComponent
                durationPickerTotalSeconds = clampDurationTotalSeconds(
                    hours: h,
                    minutes: newMins,
                    seconds: durationSecondComponent
                )
                syncPickerToDraftMinutes()
            }
        )
    }

    var durationSecondsComponentBinding: Binding<Int> {
        Binding(
            get: {
                durationSecondComponent
            },
            set: { newSecs in
                durationAutoFollowsLive = false
                let h = durationHourComponent
                durationPickerTotalSeconds = clampDurationTotalSeconds(
                    hours: h,
                    minutes: durationMinuteComponent,
                    seconds: newSecs
                )
                syncPickerToDraftMinutes()
            }
        )
    }

    func clampDurationTotalSeconds(hours: Int, minutes: Int, seconds: Int) -> Int {
        let h = min(16, max(0, hours))
        let m = max(0, min(59, minutes))
        let s = max(0, min(59, seconds))
        var total = h * 3600 + m * 60 + s
        let minSeconds = 5 * 60
        let maxSeconds = 16 * 3600
        total = max(minSeconds, min(maxSeconds, total))
        if h == 16 {
            total = maxSeconds
        }
        return total
    }

    func normalizeDurationPicker() {
        durationPickerTotalSeconds = clampDurationTotalSeconds(
            hours: durationHourComponent,
            minutes: durationMinuteComponent,
            seconds: durationSecondComponent
        )
        syncPickerToDraftMinutes()
    }

    func resetDurationPickerFromBlock() {
        if let live = block.liveDurationOverrideSeconds {
            durationPickerTotalSeconds = clampDurationTotalSeconds(
                hours: live / 3600,
                minutes: (live % 3600) / 60,
                seconds: live % 60
            )
        } else {
            durationPickerTotalSeconds = max(5, min(960, block.durationMinutes)) * 60
        }
        if block.liveDurationOverrideSeconds == nil {
            block.liveDurationOverrideSeconds = durationPickerTotalSeconds
        }
    }

    func hourRowTitle(_ hour: Int) -> String {
        "\(hour)"
    }

    func minuteRowTitle(minutes: Int) -> String {
        String(format: "%02d", minutes)
    }

    func durationDigitalLabel(totalSeconds: Int) -> String {
        let safe = max(0, totalSeconds)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let seconds = safe % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    func liveCountdownSignedSeconds(context: LiveCountdownContext, now: Date) -> Int {
        Int(context.endTime.timeIntervalSince(now))
    }

    func liveRemainingSeconds(context: LiveCountdownContext, now: Date) -> Int {
        let remaining = max(liveCountdownSignedSeconds(context: context, now: now), 0)
        return min(16 * 3600, remaining)
    }

    func liveCountdownDigitalLabel(signedSeconds: Int) -> String {
        if signedSeconds >= 0 {
            return durationDigitalLabel(totalSeconds: min(16 * 3600, signedSeconds))
        }
        return "-\(durationDigitalLabel(totalSeconds: min(16 * 3600, -signedSeconds)))"
    }

    func startDurationLiveSyncIfNeeded() {
        guard liveCountdownContext != nil else { return }
        durationLiveSyncTask?.cancel()
        durationLiveSyncTask = Task { @MainActor in
            while !Task.isCancelled, showDurationWheelSheet {
                if durationAutoFollowsLive, let context = liveCountdownContext {
                    durationPickerTotalSeconds = liveRemainingSeconds(context: context, now: Date())
                }
                syncDraftDurationFromCurrentPicker()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func syncPickerToDraftMinutes() {
        syncDraftDurationFromCurrentPicker()
    }

    func syncDraftDurationFromCurrentPicker() {
        let clamped = max(5 * 60, min(16 * 60 * 60, durationPickerTotalSeconds))
        block.liveDurationOverrideSeconds = clamped
        block.durationMinutes = max(5, min(960, Int(round(Double(clamped) / 60.0))))
    }

    func poolScopeFilterRow(
        title: String,
        systemImage: String,
        value: Binding<String>,
        anyMenuTitle: String,
        options: [String]
    ) -> some View {
        Menu {
            Button(anyMenuTitle) { value.wrappedValue = "" }
            ForEach(options, id: \.self) { option in
                Button(option) { value.wrappedValue = option }
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CueInColors.accentFocus)
                    .frame(width: 30, height: 30)
                    .background(
                        CueInColors.accentFocus.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textPrimary)
                    Text(value.wrappedValue.isEmpty ? "Any" : value.wrappedValue)
                        .font(CueInTypography.micro)
                        .foregroundStyle(value.wrappedValue.isEmpty ? CueInColors.textTertiary : CueInColors.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CueInColors.textTertiary.opacity(0.8))
            }
            .padding(.horizontal, CueInSpacing.md)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func focusTitleOnce() {
        guard !didRequestInitialFocus else { return }
        didRequestInitialFocus = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            titleFocused = true
        }
    }
}

// MARK: - Supporting Views

private struct BlockEditorPropertyChip: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(CueInTypography.captionMedium)
                .foregroundStyle(CueInColors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
        .cueInEditorGlassCapsule()
    }
}

// MARK: - Autofill pick order sheet

private struct AutofillPickOrderPickerSheet: View {
    @Binding var pickOrder: AutofillTaskPickOrder
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(AutofillTaskPickOrder.allCases, id: \.self) { mode in
                    Button {
                        pickOrder = mode
                        dismiss()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                  Text(mode.editorTitle)
                                      .font(CueInTypography.bodyMedium)
                                      .foregroundStyle(CueInColors.textPrimary)
                                  Text(mode.editorDetail)
                                      .font(CueInTypography.caption)
                                      .foregroundStyle(CueInColors.textSecondary)
                                      .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            if pickOrder == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(CueInColors.accentFocus)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(CueInColors.background)
            .navigationTitle("Autofill order")
            .cueInNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(CueInColors.textPrimary)
                }
            }
        }
    }
}

// MARK: - Appearance picker (sheet)

private struct ScheduleBlockAppearancePickerSheet: View {
    @Binding var block: ScheduleBlockDraft
    @Environment(\.dismiss) private var dismiss

    private let iconColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    private let swatchColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CueInSpacing.lg) {
                    Text("Colour")
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    LazyVGrid(columns: swatchColumns, spacing: 12) {
                        ForEach(CueInColors.scheduleBlockAppearanceHexChoices, id: \.self) { hex in
                            colourSwatch(
                                fill: CueInColors.color(hexUInt32: hex),
                                isSelected: block.timelineAccentHex == hex,
                                a11y: "Accent colour"
                            ) {
                                block.timelineAccentHex = hex
                            }
                        }
                    }

                    if block.timelineAccentHex != nil {
                        Button {
                            block.timelineAccentHex = nil
                        } label: {
                            Text("Use automatic colour")
                                .font(CueInTypography.caption)
                                .foregroundStyle(CueInColors.accentFocus)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Icon")
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .padding(.top, CueInSpacing.sm)

                    HStack(spacing: 12) {
                        Button {
                            block.timelineGlyph = nil
                        } label: {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(CueInColors.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear icon — use lane default")

                        Spacer(minLength: 0)
                    }

                    LazyVGrid(columns: iconColumns, spacing: 10) {
                        ForEach(ScheduleTimelineGlyphPalette.symbols, id: \.self) { symbol in
                            Button {
                                block.timelineGlyph = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.system(size: 20, weight: .regular))
                                    .foregroundStyle(CueInColors.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                                    .background(
                                        glyphSelected(symbol)
                                            ? CueInColors.surfaceTertiary.opacity(0.85)
                                            : CueInColors.surfacePrimary.opacity(0.35),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                        }
                    }
                }
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.bottom, CueInSpacing.xl)
            }
            .background(CueInColors.background)
            .navigationTitle("Look")
            .cueInNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CueInColors.textPrimary)
                }
            }
        }
    }

    private func glyphSelected(_ symbol: String) -> Bool {
        block.timelineGlyph == symbol
    }

    private func colourSwatch(
        fill: Color,
        isSelected: Bool,
        a11y: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: 36, height: 36)
                    .shadow(color: Color.black.opacity(0.22), radius: isSelected ? 5 : 3, y: 2)
                Circle()
                    .strokeBorder(Color.white.opacity(isSelected ? 0.95 : 0), lineWidth: isSelected ? 3 : 0)
                    .frame(width: 40, height: 40)
            }
            .frame(height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11y)
    }
}

// MARK: - TaskDropDelegate

struct TaskDropDelegate: DropDelegate {
    let item: ScheduleTaskDraft
    @Binding var list: [ScheduleTaskDraft]
    @Binding var draggedItem: ScheduleTaskDraft?

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem else { return }
        if draggedItem.id != item.id {
            guard let fromIndex = list.firstIndex(where: { $0.id == draggedItem.id }),
                  let toIndex = list.firstIndex(where: { $0.id == item.id }) else {
                return
            }
            if fromIndex != toIndex {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    list.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                }
            }
        }
    }
}

