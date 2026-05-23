import SwiftUI

// MARK: - BlockCardView
/// Minimal block row: title, one meta line, optional live progress. Tasks expand on demand.

struct BlockCardView: View {
    let block: DayBlock
    let isCurrentBlock: Bool
    let showsScheduledTime: Bool
    let showsFinishControl: Bool
    let showsCompletedToggle: Bool
    let onCompleteBlock: () -> Void
    let onRevertCompletedBlock: () -> Void
    let onToggleTask: (UUID) -> Void

    @State private var isExpanded: Bool = false

    private var effectiveExpanded: Bool {
        isCurrentBlock || isExpanded
    }

    var body: some View {
        CueInCard(
            surface: isCurrentBlock ? CueInColors.surfaceSecondary : CueInColors.surfacePrimary,
            padding: CueInSpacing.base
        ) {
            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                HStack(alignment: .top, spacing: CueInSpacing.md) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(block.title)
                            .font(CueInTypography.headline)
                            .foregroundStyle(CueInColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        metaLine
                    }

                    Spacer(minLength: CueInSpacing.sm)

                    stateIndicator
                        .padding(.top, 2)
                }

                if block.state == .active {
                    liveRunIndicator
                }

                if !block.tasks.isEmpty {
                    if effectiveExpanded {
                        expandedTasks
                    } else {
                        collapsedTaskCue
                    }
                }
            }
        }
        .opacity(block.state == .completed ? 0.48 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !block.tasks.isEmpty, !isCurrentBlock else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                isExpanded.toggle()
            }
        }
    }

    // MARK: Meta

    private var metaLine: some View {
        HStack(spacing: 6) {
            Image(systemName: block.resolvedTimelineGlyph)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CueInColors.textTertiary)

            Text(block.type.label)
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)

            Text("·")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary.opacity(0.6))

            Text("\(block.durationMinutes)m")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textSecondary)
                .monospacedDigit()

            if showsScheduledTime {
                Text("·")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary.opacity(0.6))

                Text(block.timeRangeLabel)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .monospacedDigit()
            }

            if block.isRepeatable {
                Image(systemName: "repeat")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CueInColors.textTertiary)
            }
        }
    }

    // MARK: State Indicator

    @ViewBuilder
    private var stateIndicator: some View {
        switch block.state {
        case .active:
            if showsFinishControl {
                Button(action: onCompleteBlock) {
                    Text("Done")
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(CueInColors.surfaceTertiary, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        case .completed:
            if showsCompletedToggle {
                Button(action: onRevertCompletedBlock) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(CueInColors.textSecondary)
                        .font(.system(size: 18, weight: .medium))
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(CueInColors.textTertiary)
                    .font(.system(size: 16, weight: .medium))
            }
        case .skipped:
            Image(systemName: "forward.fill")
                .foregroundStyle(CueInColors.textTertiary)
                .font(.system(size: 12))
        case .upcoming:
            EmptyView()
        }
    }

    private var liveRunIndicator: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let total = max(block.endTime.timeIntervalSince(block.startTime), 1)
            let elapsed = context.date.timeIntervalSince(block.startTime)
            let progress = min(max(elapsed / total, 0), 1)
            let remaining = block.endTime.timeIntervalSince(context.date)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(remainingLabel(for: remaining))
                        .font(CueInTypography.caption)
                        .foregroundStyle(remaining >= 0 ? CueInColors.textSecondary : CueInColors.danger)
                        .monospacedDigit()

                    Spacer(minLength: 0)

                    Text(remaining >= 0 ? "Live" : "Over")
                        .font(CueInTypography.micro)
                        .foregroundStyle(remaining >= 0 ? CueInColors.textTertiary : CueInColors.danger)
                }

                GeometryReader { geo in
                    let accent = CueInColors.resolvedTimelineAccent(blockType: block.type, hex: block.timelineAccentHex)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(CueInColors.surfaceTertiary)

                        Capsule()
                            .fill((remaining >= 0 ? accent : CueInColors.danger).opacity(0.92))
                            .frame(width: max(4, geo.size.width * progress))
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private func remainingLabel(for remaining: TimeInterval) -> String {
        let totalSeconds = Int(abs(remaining))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let base = String(format: "%d:%02d", minutes, seconds)
        return remaining >= 0 ? base : "-\(base)"
    }

    // MARK: Tasks

    private var expandedTasks: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(CueInColors.divider.opacity(0.7))
                .frame(height: 0.5)
                .padding(.vertical, CueInSpacing.xs)

            ForEach(block.tasks) { task in
                TaskRowView(task: task) {
                    onToggleTask(task.id)
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var collapsedTaskCue: some View {
        HStack(spacing: 6) {
            Text(taskSummary)
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)

            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CueInColors.textTertiary.opacity(0.7))
        }
        .padding(.top, 2)
    }

    private var taskSummary: String {
        let n = block.tasks.count
        let done = block.completedTaskCount
        if done == 0 {
            return n == 1 ? "1 task" : "\(n) tasks"
        }
        return "\(done)/\(n) tasks"
    }
}
