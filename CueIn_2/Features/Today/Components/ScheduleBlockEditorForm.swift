import SwiftUI
import UIKit

// MARK: - ScheduleBlockEditorForm
/// Shared editor: duration, ``BlockFlowMode``, scheduling flags, task source, tasks / pool fill.

private enum SavePresetBannerKind: Equatable {
    case success
    case failure
}

/// Corner radii aligned with grouped cards — slightly tighter than full-screen cards to save vertical space.
private enum BlockEditorSurface {
    static let outer: CGFloat = 18
    static let inset: CGFloat = 12
    static let chip: CGFloat = 10
}

// MARK: - Info popovers (block editor)

private enum BlockEditorInfoTopic: String, Identifiable {
    case liveRun
    case pinTime
    case priorities
    case taskSource
    case poolFill
    case savePreset

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liveRun: return "Live run"
        case .pinTime: return "Pin the time"
        case .priorities: return "When time is tight"
        case .taskSource: return "Tasks"
        case .poolFill: return "Pool scope"
        case .savePreset: return "Save to library"
        }
    }

    var message: String {
        switch self {
        case .liveRun:
            return "Blocking means the next block waits until you finish this one—the slice can run past its timer. Flowing means when the timer ends, the day can move on to what’s next."
        case .pinTime:
            return "When pinned, this block starts on the date and clock time you set. Other blocks flow before or after it instead of only following each other in order."
        case .priorities:
            return "If the day must shrink, Balanced uses the usual mix with other blocks, High priority keeps more of this block’s time when slices compress, and Fix duration holds this block’s planned length until the schedule can’t honor it."
        case .taskSource:
            return "Choose No tasks for a time-only slice. Choose Tasks to attach work: optionally turn on Autofill for matching Timeline cards, or tap the plus button for quick new-task capture (same flow as timeline quick add)."
        case .poolFill:
            return "Narrows which Timeline cards autofill can pull in: field, project, optional deep-work–only, and how candidates are ordered before packing."
        case .savePreset:
            return "Stores this block’s setup under Saved in the block library so you can reuse the shape on other days. It’s one block template, not a full schedule."
        }
    }
}

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
    @State private var infoBubbleTopic: BlockEditorInfoTopic?
    @State private var showTaskCreateSheet = false
    @State private var showAutofillPickOrderSheet = false
    @State private var showPinnedDatePicker = false
    @State private var durationPickerTotalSeconds: Int = 0
    @State private var durationAutoFollowsLive = true
    @State private var durationLiveSyncTask: Task<Void, Never>?

    @Bindable private var tasksStore = TasksStore.shared

    private enum PriorityTier: String, CaseIterable, Identifiable, Hashable {
        case balanced
        /// Sets `schedulingPriority` to 75 so compression favors keeping this block’s nominal share.
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

        /// Subtle segment fills — Balanced / High priority / Fix duration (locks nominal length when compressing).
        func segmentFill(selected: Bool) -> Color {
            switch self {
            case .balanced:
                let blue = Color(hex: 0x5E9EFF)
                return selected ? blue.opacity(0.42) : blue.opacity(0.1)
            case .highPriority:
                return selected
                    ? CueInColors.accentFocus.opacity(0.44)
                    : CueInColors.accentFocus.opacity(0.1)
            case .fixDuration:
                return selected
                    ? CueInColors.textPrimary.opacity(0.22)
                    : CueInColors.surfaceSecondary.opacity(0.55)
            }
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

        var accessibilityHint: String {
            switch self {
            case .balanced: return "Default share when the schedule shrinks."
            case .highPriority: return "Resists losing time to other blocks when the schedule shrinks."
            case .fixDuration: return "Keeps planned length until it cannot."
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            if showsAnchorNotice {
                anchorBanner
            }

            titleAccentRow

            durationSection

            flowModeSection

            schedulingSection

            sourceSection

            taskAttachmentsSection

            if onSavePreset != nil {
                savePresetControl
                    .padding(.top, CueInSpacing.xs)
            }
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
        }
        .onChange(of: block.title) { oldTitle, newTitle in
            applyTimelineGlyphSuggestionAfterTitleChange(from: oldTitle, to: newTitle)
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
            // Avoid resetting the wheel while the user is actively adjusting it.
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
    }

    private var canPersistBlockAsPreset: Bool {
        !block.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func attachCreatedPlannerTask(_ item: TaskItem) {
        block.tasks.append(
            ScheduleTaskDraft(
                title: item.title,
                isPrimary: false,
                plannerTaskItemID: item.id
            )
        )
    }

    private var savePresetControl: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            if let banner = savePresetBanner {
                savePresetBannerRow(banner)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Button(action: runSavePreset) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CueInColors.accentFocus.opacity(0.95))
                    Text("Save to library")
                        .font(CueInTypography.caption.weight(.semibold))
                    Spacer(minLength: 0)
                    editorInfoButton(for: .savePreset)
                }
                .foregroundStyle(canPersistBlockAsPreset ? CueInColors.textPrimary : CueInColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CueInSpacing.md + 2)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: BlockEditorSurface.inset, style: .continuous)
                        .fill(CueInColors.surfaceSecondary.opacity(0.96))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canPersistBlockAsPreset)
            .opacity(canPersistBlockAsPreset ? 1 : 0.44)
            .animation(.easeOut(duration: 0.28), value: savePresetBanner)
            .accessibilityHint("Copies this block into Saved blocks in the library")
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: savePresetBanner)
    }

    @ViewBuilder
    private func savePresetBannerRow(_ kind: SavePresetBannerKind) -> some View {
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
                in: RoundedRectangle(cornerRadius: BlockEditorSurface.chip, style: .continuous)
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
                in: RoundedRectangle(cornerRadius: BlockEditorSurface.chip, style: .continuous)
            )
            .accessibilityLabel("Save failed")
        }
    }

    private func runSavePreset() {
        guard let save = onSavePreset, canPersistBlockAsPreset else { return }

        UIImpactFeedbackGenerator(style: .medium).prepare()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let ok = save()

        savePresetBannerDismiss?.cancel()
        savePresetBannerDismiss = nil

        if ok {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
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
            UINotificationFeedbackGenerator().notificationOccurred(.error)
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

    /// If no explicit glyph is set, infer one from the title (`ScheduleBlockTitleGlyphSuggester`).
    private func applyInitialTimelineGlyphSuggestionIfNeeded() {
        let trimmedGlyph = block.timelineGlyph?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmedGlyph.isEmpty else { return }
        block.timelineGlyph = ScheduleBlockTitleGlyphSuggester.suggestedSymbol(for: block.title)
    }

    /// Updates the glyph from the title unless the user chose an icon that doesn’t match the previous title’s keyword suggestion.
    private func applyTimelineGlyphSuggestionAfterTitleChange(from oldTitle: String, to newTitle: String) {
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

    private func editorSettingsCard<Content: View>(
        title: String,
        infoTopic: BlockEditorInfoTopic? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title.uppercased())
                    .font(CueInTypography.micro)
                    .tracking(0.4)
                    .foregroundStyle(CueInColors.textTertiary)
                Spacer(minLength: 0)
                if let topic = infoTopic {
                    editorInfoButton(for: topic)
                }
            }
            content()
        }
        .padding(.horizontal, CueInSpacing.md)
        .padding(.vertical, CueInSpacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BlockEditorSurface.outer, style: .continuous)
                .fill(CueInColors.surfacePrimary.opacity(0.82))
        )
    }

    private func editorInfoButton(for topic: BlockEditorInfoTopic) -> some View {
        Button {
            CueInHaptics.impact(.light)
            infoBubbleTopic = topic
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(CueInColors.textTertiary.opacity(0.95))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(topic.title)")
        .popover(isPresented: Binding(
            get: { infoBubbleTopic == topic },
            set: { presented in
                if !presented { infoBubbleTopic = nil }
            }
        )) {
            editorInfoPopoverBody(for: topic)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func editorInfoPopoverBody(for topic: BlockEditorInfoTopic) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(topic.title)
                    .font(CueInTypography.caption.weight(.semibold))
                    .foregroundStyle(CueInColors.textPrimary)
                Text(topic.message)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
        .frame(maxHeight: 320)
    }

    private var anchorBanner: some View {
        Text("Timeline anchor — pool fill is off.")
            .font(CueInTypography.caption)
            .foregroundStyle(CueInColors.textSecondary)
            .padding(CueInSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CueInColors.surfacePrimary.opacity(0.55), in: RoundedRectangle(cornerRadius: BlockEditorSurface.chip, style: .continuous))
    }

    private var titleAccentRow: some View {
        HStack(alignment: .center, spacing: CueInSpacing.sm) {
            Button {
                showAppearancePicker = true
            } label: {
                Image(systemName: block.resolvedTimelineGlyph)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CueInColors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(
                        CueInColors.resolvedTimelineAccent(
                            blockType: block.timelineAccent,
                            hex: block.timelineAccentHex
                        ).opacity(0.38),
                        in: RoundedRectangle(cornerRadius: BlockEditorSurface.inset, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose colour and icon")

            TextField("Title", text: $block.title)
                .font(CueInTypography.bodyMedium)
                .foregroundStyle(CueInColors.textPrimary)
                .padding(.horizontal, CueInSpacing.md)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: BlockEditorSurface.inset, style: .continuous))

            if showsPresetLibrary {
                Button {
                    showPresetSheet = true
                } label: {
                    Image(systemName: "square.stack.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CueInColors.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: BlockEditorSurface.inset, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Block library")
                .accessibilityHint("Reuse a saved block or pick from sample day blocks")
            }
        }
    }

    private var schedulingSection: some View {
        editorSettingsCard(title: "Schedule") {
            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                HStack(alignment: .center, spacing: CueInSpacing.sm) {
                    Toggle(isOn: $block.pinsToClock) {
                        Text("Pin start")
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textSecondary)
                    }
                    .tint(CueInColors.accentFixed)
                    .disabled(!allowsFixedClockEdit)

                    Spacer(minLength: 0)

                    editorInfoButton(for: .pinTime)
                }

                if block.pinsToClock, allowsFixedClockEdit {
                    pinnedStartControls
                }

                HStack(alignment: .center, spacing: CueInSpacing.sm) {
                    prioritySegmentsView
                        .frame(maxWidth: .infinity, alignment: .leading)
                    editorInfoButton(for: .priorities)
                }
                .padding(.top, CueInSpacing.xs)
            }
        }
    }

    private var prioritySegmentsView: some View {
        let selection = PriorityTier(
            schedulingPriority: block.schedulingPriority,
            locksPlannedDuration: block.locksPlannedDuration
        )
        return HStack(spacing: 8) {
            ForEach(PriorityTier.allCases) { tier in
                let isOn = selection == tier
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        tier.apply(to: $block)
                    }
                } label: {
                    Text(tier.label)
                        .font(CueInTypography.caption.weight(isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? CueInColors.textPrimary : CueInColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.72)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 2)
                        .background(
                            RoundedRectangle(cornerRadius: BlockEditorSurface.chip, style: .continuous)
                                .fill(tier.segmentFill(selected: isOn))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tier.label)
                .accessibilityHint(tier.accessibilityHint)
            }
        }
    }

    private var pinnedStartControls: some View {
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
                    CueInColors.surfaceSecondary.opacity(0.45),
                    in: RoundedRectangle(cornerRadius: BlockEditorSurface.inset, style: .continuous)
                )

                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                        showPinnedDatePicker.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 13, weight: .semibold))
                        Text(pinnedDateShortLabel)
                            .font(CueInTypography.micro)
                            .monospacedDigit()
                    }
                    .foregroundStyle(CueInColors.textPrimary)
                    .padding(.horizontal, 10)
                    .frame(height: 40)
                    .background(
                        CueInColors.surfaceSecondary.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: BlockEditorSurface.inset, style: .continuous)
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
                    CueInColors.surfaceSecondary.opacity(0.45),
                    in: RoundedRectangle(cornerRadius: BlockEditorSurface.inset, style: .continuous)
                )
            }
        }
    }

    private var fixedStartBinding: Binding<Date> {
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

    private var fixedDateBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.startOfDay(for: block.fixedClockDate ?? Date())
            },
            set: { newDate in
                block.fixedClockDate = Calendar.current.startOfDay(for: newDate)
            }
        )
    }

    private var pinnedDateShortLabel: String {
        let date = block.fixedClockDate ?? Date()
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }

    private var sourceSection: some View {
        editorSettingsCard(title: "Tasks", infoTopic: .taskSource) {
            CueInLiquidGlassSegmentStrip(
                segments: [
                    CueInLiquidGlassSegmentStrip.Segment(
                        id: "none",
                        title: "No tasks",
                        systemImage: "circle.dashed",
                        accessibilityHint: "Time block without checklist or pool."
                    ),
                    CueInLiquidGlassSegmentStrip.Segment(
                        id: "tasks",
                        title: "Tasks",
                        systemImage: "checkmark.circle.fill",
                        accessibilityHint: "Attach Timeline pool fill and/or real tasks from the Tasks tab."
                    ),
                ],
                selectionID: block.assignsTasks ? "tasks" : "none",
                onSelect: { raw in
                    let wantsTasks = raw == "tasks"
                    guard wantsTasks != block.assignsTasks else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        block.assignsTasks = wantsTasks
                        if !wantsTasks {
                            block.poolFillEnabled = false
                            block.tasks = []
                            block.deepWorkOnly = false
                        }
                    }
                }
            )
        }
    }

    private var taskAttachmentsSection: some View {
        Group {
            if block.assignsTasks {
                VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                    if allowsPoolFillSource {
                        poolFillToggleRow
                            .disabled(!allowsPoolFillSource)
                            .opacity(allowsPoolFillSource ? 1 : 0.45)
                    }

                    linkedTasksSection

                    if block.poolFillEnabled, allowsPoolFillSource {
                        poolFillSection
                    }
                }
            }
        }
    }

    private var poolFillToggleRow: some View {
        HStack(alignment: .center, spacing: CueInSpacing.md) {
            Text("Autofill")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textSecondary)
            Spacer(minLength: 0)
            Toggle("", isOn: $block.poolFillEnabled)
                .labelsHidden()
                .tint(CueInColors.accentFocus)
        }
        .padding(.horizontal, CueInSpacing.md)
        .padding(.vertical, 9)
        .modifier(CueInLiquidGlassToggleShellModifier())
        .accessibilityHint("When on, matching Timeline tasks can be added automatically; you can still add or create tasks yourself.")
    }

    private var linkedTasksSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.xs) {
            HStack(alignment: .center, spacing: CueInSpacing.sm) {
                Text("Tasks")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                Spacer(minLength: 0)
                Button {
                    showTaskCreateSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(CueInColors.accentFocus)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New task")
                .accessibilityHint("Opens quick capture to add a task here")
            }

            if block.tasks.isEmpty {
                Text("No tasks")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 4) {
                    ForEach($block.tasks) { $task in
                        HStack(spacing: CueInSpacing.sm) {
                            Text(displayTitle(for: task))
                                .font(CueInTypography.caption)
                                .foregroundStyle(CueInColors.textPrimary)
                                .lineLimit(2)

                            Spacer(minLength: 0)

                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                    block.tasks.removeAll { $0.id == task.id }
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(CueInColors.textTertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove from block")
                        }
                        .padding(.horizontal, CueInSpacing.md)
                        .padding(.vertical, 6)
                        .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: BlockEditorSurface.inset, style: .continuous))
                    }
                }
            }
        }
    }

    private func displayTitle(for task: ScheduleTaskDraft) -> String {
        if let pid = task.plannerTaskItemID,
           let item = tasksStore.tasks.first(where: { $0.id == pid }) {
            return item.title
        }
        let trimmed = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    private var durationSection: some View {
        editorSettingsCard(title: "Planned duration") {
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
                HStack(spacing: CueInSpacing.md) {
                    durationButtonLabel
                    Spacer(minLength: 0)
                    if allowsDurationOverride {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CueInColors.textTertiary)
                    } else {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CueInColors.warning.opacity(0.9))
                    }
                }
                .padding(.horizontal, CueInSpacing.md)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: BlockEditorSurface.inset, style: .continuous)
                        .fill(
                            allowsDurationOverride
                                ? CueInColors.surfaceSecondary.opacity(0.42)
                                : CueInColors.warning.opacity(0.12)
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Planned duration, \(ScheduleBlockFormat.durationLabel(minutes: block.durationMinutes))")
            .accessibilityHint(
                allowsDurationOverride
                    ? "Opens hour, minute, and second picker"
                    : "Duration is locked because this block comes from a pinned task"
            )
        }
    }

    @ViewBuilder
    private var durationButtonLabel: some View {
        if let context = liveCountdownContext, durationAutoFollowsLive {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(durationDigitalLabel(totalSeconds: liveRemainingSeconds(context: context, now: timeline.date)))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(CueInColors.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        } else {
            Text(durationDigitalLabel(totalSeconds: durationPickerTotalSeconds))
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(CueInColors.textPrimary)
                .monospacedDigit()
        }
    }

    private var flowModeSection: some View {
        editorSettingsCard(title: "Live run", infoTopic: .liveRun) {
            CueInLiquidGlassSegmentStrip(
                segments: BlockFlowMode.allCases.map {
                    CueInLiquidGlassSegmentStrip.Segment(
                        id: $0.rawValue,
                        title: $0.label,
                        systemImage: $0.editorIconName,
                        accessibilityHint: $0.scheduleEditorHint
                    )
                },
                selectionID: block.flowMode.rawValue,
                onSelect: { raw in
                    guard let mode = BlockFlowMode(rawValue: raw) else { return }
                    block.flowMode = mode
                }
            )
        }
    }

    private var durationWheelSheet: some View {
        NavigationStack {
            VStack(spacing: CueInSpacing.sm) {
                HStack(spacing: 0) {
                    Picker("Hours", selection: durationHoursBinding) {
                        ForEach(0...16, id: \.self) { hour in
                            Text(hourRowTitle(hour)).tag(hour)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Picker("Minutes", selection: durationMinutesComponentBinding) {
                        ForEach(0...59, id: \.self) { mins in
                            Text(minuteRowTitle(minutes: mins)).tag(mins)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Picker("Seconds", selection: durationSecondsComponentBinding) {
                        ForEach(0...59, id: \.self) { secs in
                            Text(minuteRowTitle(minutes: secs)).tag(secs)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 180)
                .clipped()

            }
            .padding(.top, 8)
            .navigationTitle("Timer")
            .navigationBarTitleDisplayMode(.inline)
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

    /// Hour component 0...16 derived from total picker seconds.
    private var durationHourComponent: Int {
        min(16, durationPickerTotalSeconds / 3600)
    }

    private var durationMinuteComponent: Int {
        (durationPickerTotalSeconds % 3600) / 60
    }

    private var durationSecondComponent: Int {
        durationPickerTotalSeconds % 60
    }

    private var durationHoursBinding: Binding<Int> {
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

    private var durationMinutesComponentBinding: Binding<Int> {
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

    private var durationSecondsComponentBinding: Binding<Int> {
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

    private func clampDurationTotalSeconds(hours: Int, minutes: Int, seconds: Int) -> Int {
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

    private func normalizeDurationPicker() {
        durationPickerTotalSeconds = clampDurationTotalSeconds(
            hours: durationHourComponent,
            minutes: durationMinuteComponent,
            seconds: durationSecondComponent
        )
        syncPickerToDraftMinutes()
        resetDurationPickerFromBlock()
    }

    private func resetDurationPickerFromBlock() {
        durationPickerTotalSeconds = max(5, min(960, block.durationMinutes)) * 60
        if block.liveDurationOverrideSeconds == nil {
            block.liveDurationOverrideSeconds = durationPickerTotalSeconds
        }
    }

    private func hourRowTitle(_ hour: Int) -> String {
        "\(hour)"
    }

    private func minuteRowTitle(minutes: Int) -> String {
        String(format: "%02d", minutes)
    }

    private func durationDigitalLabel(totalSeconds: Int) -> String {
        let safe = max(0, totalSeconds)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let seconds = safe % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func liveRemainingSeconds(context: LiveCountdownContext, now: Date) -> Int {
        let remaining = max(Int(context.endTime.timeIntervalSince(now)), 0)
        return min(16 * 3600, remaining)
    }

    private func startDurationLiveSyncIfNeeded() {
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

    private func syncPickerToDraftMinutes() {
        syncDraftDurationFromCurrentPicker()
    }

    /// Keeps the draft in lock-step with the visible countdown/picker value so Save
    /// uses the exact "now" timer value (not the value from when the user first edited).
    private func syncDraftDurationFromCurrentPicker() {
        let clamped = max(5 * 60, min(16 * 60 * 60, durationPickerTotalSeconds))
        block.liveDurationOverrideSeconds = clamped
        block.durationMinutes = max(5, min(960, Int(round(Double(clamped) / 60.0))))
    }

    private var poolFillSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            HStack(alignment: .top, spacing: CueInSpacing.sm) {
                Text("Pool filters")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                editorInfoButton(for: .poolFill)
                Spacer(minLength: 0)
                Text(block.fillRule.displayLabel)
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
                    .multilineTextAlignment(.trailing)
            }

            VStack(spacing: 0) {
                poolScopeFilterRow(
                    title: "Field",
                    systemImage: "square.grid.2x2",
                    value: $block.fillField,
                    anyMenuTitle: "Any field",
                    options: availableScopes.fields
                )
                poolScopeDivider
                poolScopeFilterRow(
                    title: "Project",
                    systemImage: "folder",
                    value: $block.fillProject,
                    anyMenuTitle: "Any project",
                    options: availableScopes.projects
                )
            }
            .background(
                RoundedRectangle(cornerRadius: BlockEditorSurface.outer, style: .continuous)
                    .fill(CueInColors.surfacePrimary.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BlockEditorSurface.outer, style: .continuous)
                    .strokeBorder(CueInColors.divider.opacity(0.32), lineWidth: 0.5)
            )

            Button {
                showAutofillPickOrderSheet = true
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CueInColors.accentFocus)
                        .frame(width: 30, height: 30)
                        .background(
                            CueInColors.accentFocus.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Choose tasks by")
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textPrimary)
                        Text(block.autofillPickOrder.editorTitle)
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Change")
                        .font(CueInTypography.caption.weight(.semibold))
                        .foregroundStyle(CueInColors.accentFocus)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CueInColors.textTertiary.opacity(0.85))
                }
                .padding(.horizontal, CueInSpacing.md)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: BlockEditorSurface.inset, style: .continuous)
                        .fill(CueInColors.surfaceSecondary.opacity(0.38))
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens autofill ordering options")

            Toggle(isOn: $block.deepWorkOnly) {
                HStack(spacing: 10) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CueInColors.accentFocus.opacity(0.75))
                    Text("Deep work only")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textSecondary)
                }
            }
            .tint(CueInColors.accentFocus)
        }
    }

    private var poolScopeDivider: some View {
        Rectangle()
            .fill(CueInColors.divider.opacity(0.4))
            .frame(height: 0.5)
            .padding(.leading, 54)
    }

    private func poolScopeFilterRow(
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(CueInColors.textPrimary)
                }
            }
        }
    }
}

// MARK: - Appearance picker (sheet — avoids broken Menu rendering & endless icon lists)

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
                                        in: RoundedRectangle(cornerRadius: BlockEditorSurface.inset, style: .continuous)
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
            .navigationBarTitleDisplayMode(.inline)
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
