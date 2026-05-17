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
            // Vertical scroll + non-empty title so the system navigation bar matches other Today sheets.
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
                    onDurationCommit: commitDurationImmediately,
                    allowsDurationOverride: allowsDurationOverride,
                    durationOverrideWarning: durationOverrideWarning
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.bottom, CueInSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(CueInColors.background)
            .navigationTitle("Block")
            .cueInNavigationBarTitleDisplayMode(.inline)
            .cueInNavigationToolbarColorScheme()
            .toolbar {
                CueInEditorToolbar(
                    saveEnabled: !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onClose: onCancel,
                    onSave: saveTapped
                ) {
                    Text("Block")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CueInColors.textPrimary)
                        .lineLimit(1)
                }
            }
        }
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
