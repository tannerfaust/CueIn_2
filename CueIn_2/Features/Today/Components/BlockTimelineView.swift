import SwiftUI

// MARK: - BlockTimelineView
/// Vertical timeline connector between block cards.
/// Thin line with time labels creating the "day frame" structure.

struct BlockTimelineView: View {
    let blocks: [DayBlock]
    let currentBlockID: UUID?
    let showsScheduledTime: Bool
    let showsFinishControl: Bool
    let showsCompletedToggle: Bool
    let onToggleTask: (UUID, UUID) -> Void
    let onCompleteBlock: (UUID) -> Void
    let onRevertCompletedBlock: (UUID) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: CueInSpacing.md) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                VStack(alignment: .leading, spacing: 0) {
                    if showsScheduledTime, index > 0 {
                        timeConnector(from: blocks[index - 1], to: block)
                    }

                    BlockCardView(
                        block: block,
                        isCurrentBlock: block.id == currentBlockID,
                        showsScheduledTime: showsScheduledTime,
                        showsFinishControl: showsFinishControl,
                        showsCompletedToggle: showsCompletedToggle,
                        onCompleteBlock: { onCompleteBlock(block.id) },
                        onRevertCompletedBlock: { onRevertCompletedBlock(block.id) },
                        onToggleTask: { taskID in
                            onToggleTask(block.id, taskID)
                        }
                    )
                    .id(block.id)
                }
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.top, CueInSpacing.sm)
    }

    // MARK: - Time Connector

    @ViewBuilder
    private func timeConnector(from previous: DayBlock, to next: DayBlock) -> some View {
        let gap = next.startTime.timeIntervalSince(previous.endTime)
        let hasGap = gap > 60 // More than 1 minute gap

        HStack(spacing: 0) {
            // Left time labels
            VStack(spacing: 0) {
                if hasGap {
                    Text(timeLabel(previous.endTime))
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                        .monospacedDigit()
                }
            }
            .frame(width: 40, alignment: .trailing)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(CueInColors.divider)
                    .frame(width: 1)
                    .frame(height: hasGap ? 28 : 16)
            }
            .padding(.horizontal, CueInSpacing.md)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func timeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
