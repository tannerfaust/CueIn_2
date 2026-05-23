import SwiftUI

// MARK: - ScheduleBlockEditSheet
/// Block editor for a live formula block on Today (uses ``ScheduleBlockEditorForm``).

struct ScheduleBlockEditSheet: View {
    private let allowsPoolFillSource: Bool
    private let allowsFixedClockEdit: Bool
    private let allowsDurationOverride: Bool
    private let durationOverrideWarning: String?
    private let liveCountdownContext: ScheduleBlockEditorForm.LiveCountdownContext?

    @State private var draft: ScheduleBlockDraft
    let availableScopes: ScheduleMakerTaskScopes

    @AppStorage(TodayDisplayPreferences.enableCategoryTracking) private var enableCategoryTracking = false
    @State private var customCategories: [String] = UserDefaults.standard.stringArray(forKey: "today.schedule.customCategories") ?? []
    @State private var showingNewCategoryAlert = false
    @State private var newCategoryName = ""

    private var allCategories: [String] {
        var list = ["Work", "Others"]
        for cat in customCategories {
            let trimmed = cat.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !list.contains(trimmed) {
                list.append(trimmed)
            }
        }
        return list
    }

    let onSave: (ScheduleBlockDraft) -> Void
    let onCancel: () -> Void

    init(
        block: DayBlock,
        availableScopes: ScheduleMakerTaskScopes,
        onSave: @escaping (ScheduleBlockDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        allowsPoolFillSource = !block.isAnchorBlock
        allowsFixedClockEdit = !block.isAnchorBlock
        let hasPinnedSourceTask = block.tasks.contains { $0.sourceExecutionTaskID != nil }
        allowsDurationOverride = !(block.isAnchorBlock || hasPinnedSourceTask)
        durationOverrideWarning = allowsDurationOverride
            ? nil
            : "Pinned tasks own their fixed start and end times, so duration override is disabled for this block."
        if block.state == .active {
            liveCountdownContext = ScheduleBlockEditorForm.LiveCountdownContext(
                startTime: block.startTime,
                endTime: block.endTime
            )
        } else {
            liveCountdownContext = nil
        }
        _draft = State(initialValue: ScheduleBlockDraft(from: block))
        self.availableScopes = availableScopes
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CueInColors.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    ScheduleBlockEditorForm(
                        block: $draft,
                        availableScopes: availableScopes,
                        allowsPoolFillSource: allowsPoolFillSource,
                        showsAnchorNotice: !allowsPoolFillSource,
                        allowsFixedClockEdit: allowsFixedClockEdit,
                        showsPresetLibrary: true,
                        createdTasksGoToToday: true,
                        onSavePreset: {
                            let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return false }
                            return FormulaLibraryService.saveCustomBlockPreset(draft.toFormulaBlockTemplate())
                        },
                        liveCountdownContext: liveCountdownContext,
                        allowsDurationOverride: allowsDurationOverride,
                        durationOverrideWarning: durationOverrideWarning
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, CueInSpacing.screenHorizontal)
                    .padding(.top, CueInSpacing.sm)
                    .padding(.bottom, CueInSpacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Block")
            .cueInNavigationBarTitleDisplayMode(.inline)
            .cueInNavigationToolbarColorScheme()
            .toolbar {
                CueInEditorToolbar(
                    saveEnabled: !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onClose: onCancel,
                    onSave: saveTapped
                ) {
                    Menu {
                        ForEach(allCategories, id: \.self) { cat in
                            Button {
                                draft.category = cat
                                draft.isCategoryManuallySet = true
                            } label: {
                                HStack {
                                    Text(cat)
                                    if draft.category == cat {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button {
                            newCategoryName = ""
                            showingNewCategoryAlert = true
                        } label: {
                            Label("New Category...", systemImage: "plus")
                        }
                    } label: {
                        CueInEditorCategoryChip(category: draft.category)
                    }
                }
            }
            .alert("New Category", isPresented: $showingNewCategoryAlert) {
                TextField("Category name", text: $newCategoryName)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) { }
                Button("Create") {
                    let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        var updated = customCategories
                        if !updated.contains(trimmed) {
                            updated.append(trimmed)
                            customCategories = updated
                            UserDefaults.standard.set(updated, forKey: "today.schedule.customCategories")
                        }
                        draft.category = trimmed
                        draft.isCategoryManuallySet = true
                    }
                }
            } message: {
                Text("Enter a name for the new category.")
            }
        }
        .cueInPreferredColorScheme()
    }

    private func saveTapped() {
        commitEdits()
    }

    private func commitDurationImmediately() {
        commitEdits()
    }

    private func commitEdits() {
        let t = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if !allowsPoolFillSource {
            draft.poolFillEnabled = false
            draft.assignsTasks = true
        }
        onSave(draft)
    }
}

#Preview {
    let start = Date()
    let end = start.addingTimeInterval(90 * 60)
    ScheduleBlockEditSheet(
        block: DayBlock(
            title: "Focus",
            type: .focus,
            state: .upcoming,
            startTime: start,
            endTime: end
        ),
        availableScopes: .empty,
        onSave: { _ in },
        onCancel: { }
    )
    .cueInPreferredColorScheme()
}

struct CueInEditorCategoryChip: View {
    let category: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tag.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CueInColors.textSecondary)
            Text(category)
                .font(CueInTypography.captionMedium)
                .foregroundStyle(CueInColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(CueInColors.textTertiary)
        }
        .padding(.horizontal, 13)
        .frame(height: 38)
        .cueInEditorGlassCapsule()
    }
}
