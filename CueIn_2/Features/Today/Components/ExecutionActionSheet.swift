import SwiftUI

// MARK: - ExecutionActionSheet
/// Bottom sheet for run controls: timeline pause/resume/snap in task-led mode,
/// and start/stop/reset in formula mode.

struct ExecutionActionSheet: View {
    let onDismiss: () -> Void

    private let viewModel = TodayViewModel.shared
    @AppStorage(TodayDisplayPreferences.pullsTasksFromExecutionPool) private var pullsTasksFromExecutionPool = true

    var body: some View {
        CueInBottomSheet(title: viewModel.isTaskLedMode ? "Execution" : "Day run", onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                if viewModel.isTaskLedMode {
                    taskLedSection
                } else {
                    formulaSection
                }
            }
        }
    }

    // MARK: - Task-led

    @ViewBuilder
    private var taskLedSection: some View {
        SheetActionRow(
            icon: viewModel.isExecutionPaused ? "play.fill" : "pause.fill",
            title: viewModel.isExecutionPaused ? "Resume Execution" : "Pause Execution",
            subtitle: pauseSubtitle,
            tint: CueInColors.accentFocus
        ) {
            if viewModel.isExecutionPaused {
                viewModel.resumeTimelineExecution()
            } else {
                viewModel.pauseTimelineExecution()
            }
            onDismiss()
        }

        SheetActionRow(
            icon: "arrow.right.to.line",
            title: "Start from Now",
            subtitle: "Snap all upcoming tasks to start from this moment",
            tint: Color(red: 0.42, green: 0.82, blue: 0.55)
        ) {
            viewModel.startTimelineExecution()
            onDismiss()
        }
    }

    // MARK: - Formula

    @ViewBuilder
    private var formulaSection: some View {
        if viewModel.isFormulaSchedulePaused {
            SheetActionRow(
                icon: "play.fill",
                title: "Resume TimeMap",
                subtitle: "Continue the run; time blocks shift by the time you were paused",
                tint: CueInColors.accentFocus
            ) {
                viewModel.resumeFormulaScheduleAfterPause()
                onDismiss()
            }
        }

        if viewModel.isFormulaRunLive, !viewModel.isFormulaSchedulePaused {
            SheetActionRow(
                icon: "checkmark.circle",
                title: "Finish Current Block",
                subtitle: "Mark this time block complete and move the TimeMap forward",
                tint: Color(red: 0.42, green: 0.82, blue: 0.55)
            ) {
                viewModel.finishActiveBlock()
                onDismiss()
            }
            .disabled(viewModel.currentBlock == nil)

            SheetActionRow(
                icon: "pause.fill",
                title: "Pause TimeMap",
                subtitle: "Freeze time blocks and timeline; day progress keeps moving",
                tint: CueInColors.accentFocus
            ) {
                viewModel.pauseFormulaSchedule()
                onDismiss()
            }
        }

        if viewModel.isFormulaRunLive {
            Toggle(isOn: $pullsTasksFromExecutionPool) {
                Label("Use execution pool for tasks", systemImage: "tray.full")
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textPrimary)
            }
            .tint(CueInColors.accentFocus)
            .padding(.horizontal, CueInSpacing.md)
            .padding(.vertical, CueInSpacing.sm)
            .background(CueInColors.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
        }

        if viewModel.isFormulaPreviewing || viewModel.isFormulaRunStopped {
            SheetActionRow(
                icon: "play.fill",
                title: viewModel.isFormulaRunStopped ? "Resume Day" : "Start Day",
                subtitle: viewModel.isFormulaRunStopped
                    ? "Continue the TimeMap run from where you left off"
                    : "Lock times and begin the first time block",
                tint: CueInColors.accentFocus
            ) {
                if viewModel.isFormulaRunStopped {
                    viewModel.startFormulaDay()
                } else {
                    NotificationCenter.default.post(name: .cueInShowScheduleStartSetup, object: nil)
                }
                onDismiss()
            }
        }

        if viewModel.isFormulaRunStopped {
            SheetActionRow(
                icon: "arrow.counterclockwise",
                title: "Reset to Preview",
                subtitle: "Discard this run and edit the TimeMap layout again",
                tint: CueInColors.textSecondary
            ) {
                viewModel.restartFormulaDay()
                onDismiss()
            }
        }

        if viewModel.isFormulaRunLive || viewModel.isFormulaSchedulePaused {
            SheetActionRow(
                icon: "arrow.counterclockwise",
                title: "Reset TimeMap",
                subtitle: "Discard this run and return to the editable TimeMap",
                tint: CueInColors.textSecondary
            ) {
                viewModel.restartFormulaDay()
                onDismiss()
            }
        }

        if viewModel.isFormulaRunLive || viewModel.isFormulaSchedulePaused || viewModel.isFormulaRunStopped {
            SheetActionRow(
                icon: "calendar.badge.minus",
                title: "Clear the TimeMap",
                subtitle: "Remove the current TimeMap from Today",
                tint: Color.red
            ) {
                viewModel.clearSchedule()
                onDismiss()
            }
            .disabled(!viewModel.canClearFormulaSchedule)
        }
    }

    // MARK: - Helpers

    private var pauseSubtitle: String {
        if viewModel.isExecutionPaused, let pausedAt = viewModel.executionPausedAt {
            let minutes = Int(Date().timeIntervalSince(pausedAt) / 60)
            let durationText = minutes < 1 ? "just now" : (minutes == 1 ? "1 min ago" : "\(minutes) min ago")
            return "Paused \(durationText) — resuming shifts tasks forward"
        }
        return "Hold task times while you take a break"
    }
}

#Preview {
    ZStack {
        CueInColors.background.ignoresSafeArea()
        ExecutionActionSheet(onDismiss: {})
    }
    .cueInPreferredColorScheme()
}
