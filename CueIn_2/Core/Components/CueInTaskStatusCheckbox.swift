import SwiftUI

// MARK: - CueInTaskStatusCheckbox
/// Task checkbox: **Done** uses success fill; open workflow states share neutral grey rings with distinct geometry.

struct CueInTaskStatusCheckbox: View {
    var isCompleted: Bool
    /// When incomplete, selects the ring motif. Use `nil` for block / lead lists (neutral “queued” look).
    var workflowStatus: TaskStatus? = nil
    var diameter: CGFloat = 20
    /// Applied when complete (e.g. brief spring overshoot).
    var completeScale: CGFloat = 1

    private var doneFill: Color { CueInColors.success }
    private var openStroke: Color { CueInColors.textTertiary }
    private var openStrokeStrong: Color { CueInColors.textSecondary.opacity(0.72) }

    var body: some View {
        ZStack {
            if isCompleted {
                completedCore
            } else {
                incompleteCore
            }
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(isCompleted ? completeScale : 1)
    }

    // MARK: Complete

    private var completedCore: some View {
        ZStack {
            Circle()
                .fill(doneFill.opacity(0.94))
            Circle()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: max(0.5, diameter * 0.06))
            Image(systemName: "checkmark")
                .font(.system(size: diameter * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.96))
        }
    }

    // MARK: Incomplete

    @ViewBuilder
    private var incompleteCore: some View {
        switch resolvedIncomplete {
        case .inbox:
            Circle()
                .strokeBorder(
                    openStroke.opacity(0.95),
                    style: StrokeStyle(lineWidth: diameter * 0.068, lineCap: .round, dash: [4, 3.5])
                )
        case .scheduled:
            Circle()
                .strokeBorder(openStrokeStrong.opacity(0.95), lineWidth: diameter * 0.072)
        case .active:
            ZStack {
                Circle()
                    .strokeBorder(openStrokeStrong.opacity(0.98), lineWidth: diameter * 0.095)
                Circle()
                    .fill(openStrokeStrong.opacity(0.55))
                    .frame(width: diameter * 0.28, height: diameter * 0.28)
            }
        case .paused:
            ZStack {
                Circle()
                    .strokeBorder(CueInColors.warning.opacity(0.55), lineWidth: diameter * 0.072)
                RoundedRectangle(cornerRadius: diameter * 0.06, style: .continuous)
                    .fill(CueInColors.warning.opacity(0.88))
                    .frame(width: diameter * 0.22, height: diameter * 0.26)
            }
        case .archived:
            Circle()
                .strokeBorder(
                    openStroke.opacity(0.72),
                    style: StrokeStyle(lineWidth: diameter * 0.055, lineCap: .round, dash: [1.5, 4])
                )
        case .queuedInBlock:
            Circle()
                .strokeBorder(openStroke.opacity(0.88), lineWidth: diameter * 0.07)
        }
    }

    private enum IncompleteKind {
        case inbox, scheduled, active, paused, archived, queuedInBlock
    }

    private var resolvedIncomplete: IncompleteKind {
        guard let s = workflowStatus else { return .queuedInBlock }
        switch s {
        case .inbox: return .inbox
        case .scheduled: return .scheduled
        case .active: return .active
        case .paused: return .paused
        case .archived: return .archived
        case .completed: return .queuedInBlock
        }
    }
}
