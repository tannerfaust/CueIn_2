import SwiftUI

// MARK: - ScheduleStartSetupSheet
/// Preflight before a Schedule becomes a live run.

struct ScheduleStartSetupSheet: View {
    let preview: ScheduleStartPreview
    @Binding var draftScheduleEnd: Date
    let onStart: (Date) -> Void
    let onIssueAction: (ScheduleStartPreflightAction) -> Void
    let onCancel: () -> Void

    private var sheetNavigationTitle: String {
        preview.hasBlockingIssues ? "Resolve before start" : "Start schedule"
    }

    var body: some View {
        CueInBottomSheet(title: sheetNavigationTitle, onDismiss: onCancel) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: CueInSpacing.lg) {
                    header
                    runSnapshot
                    endControl
                    preflightPanel
                    planningNote
                    startButton
                    cancelButton
                }
                .padding(.bottom, CueInSpacing.sm)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: CueInSpacing.md) {
            Image(systemName: preview.hasBlockingIssues ? "exclamationmark.triangle.fill" : "play.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(headerTint)
                .frame(width: 42, height: 42)
                .background(headerTint.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: CueInSpacing.xs) {
                HStack {
                    Spacer(minLength: 0)
                    Text(preview.hasBlockingIssues ? "Blocked" : "Ready")
                        .font(CueInTypography.micro)
                        .foregroundStyle(headerTint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(headerTint.opacity(0.13), in: Capsule(style: .continuous))
                }

                Text(preview.hasBlockingIssues
                     ? "Pinned-time conflicts need a decision before the run can lock."
                     : "Review the window, then start the live run.")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var runSnapshot: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            Text("Run snapshot")
                .font(CueInTypography.captionMedium)
                .foregroundStyle(CueInColors.textTertiary)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: CueInSpacing.sm),
                    GridItem(.flexible(), spacing: CueInSpacing.sm)
                ],
                spacing: CueInSpacing.sm
            ) {
                metricTile(value: "\(preview.blockCount)", label: "Blocks", icon: "rectangle.stack.fill")
                metricTile(value: Self.durationLabel(minutes: preview.nominalMinutes), label: "Planned", icon: "clock.fill")
                metricTile(value: "\(preview.openExecutionTaskCount)", label: "Open tasks", icon: "tray.full.fill")
                metricTile(value: "\(preview.pinnedBlockCount)", label: "Pinned", icon: "pin.fill", tint: preview.pinnedBlockCount > 0 ? CueInColors.warning : CueInColors.textTertiary)
            }
        }
        .padding(CueInSpacing.md)
        .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CueInColors.cardBorder, lineWidth: 1)
        }
    }

    private var endControl: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            HStack {
                Text("End schedule")
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(CueInColors.textTertiary)

                Spacer()

                Text(windowLabel)
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textSecondary)
                    .monospacedDigit()
            }

            DatePicker(
                "Schedule end",
                selection: $draftScheduleEnd,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .tint(CueInColors.textPrimary)
        }
        .padding(CueInSpacing.md)
        .background(CueInColors.surfaceSecondary.opacity(0.74), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var preflightPanel: some View {
        if preview.preflightIssues.isEmpty {
            VStack(alignment: .leading, spacing: CueInSpacing.md) {
                Label(preview.blockCount == 0 ? "No blocks for today" : "No blockers found", systemImage: preview.blockCount == 0 ? "calendar.badge.exclamationmark" : "checkmark.seal.fill")
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(preview.blockCount == 0 ? CueInColors.warning : CueInColors.success)

                Text(preview.blockCount == 0 ? "Future pinned blocks are kept in Hub Planning and will not start in today’s run." : "The schedule can start with the selected end time.")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
            }
            .padding(CueInSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((preview.blockCount == 0 ? CueInColors.warning : CueInColors.success).opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: CueInSpacing.md) {
                HStack(alignment: .top, spacing: CueInSpacing.sm) {
                    Image(systemName: preview.hasBlockingIssues ? "exclamationmark.octagon.fill" : "clock.badge.exclamationmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(headerTint)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(preview.hasBlockingIssues ? "Action required" : "Heads up")
                            .font(CueInTypography.captionMedium)
                            .foregroundStyle(CueInColors.textPrimary)
                        Text(preview.hasBlockingIssues
                             ? "Choose how to handle each blocking conflict."
                             : "These changes are optional, but they affect how the run feels.")
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                    ForEach(preview.preflightIssues) { issue in
                        preflightIssueRow(issue)
                    }
                }

                if let recommendedEnd = preview.recommendedMinimumEnd,
                   recommendedEnd > draftScheduleEnd {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            draftScheduleEnd = recommendedEnd
                        }
                    } label: {
                        HStack(spacing: CueInSpacing.sm) {
                            Image(systemName: "wand.and.stars")
                            Text("Use safe end")
                            Spacer()
                            Text(Self.timeLabel(recommendedEnd))
                                .monospacedDigit()
                        }
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(CueInColors.background)
                        .padding(.horizontal, CueInSpacing.md)
                        .padding(.vertical, 10)
                        .background(CueInColors.textPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(CueInSpacing.md)
            .background(headerTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(headerTint.opacity(0.30), lineWidth: 1)
            }
        }
    }

    private func preflightIssueRow(_ issue: ScheduleStartPreflightIssue) -> some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            HStack(alignment: .top, spacing: CueInSpacing.sm) {
                Image(systemName: issue.severity.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(issue.severity.tint)
                    .frame(width: 20)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(issue.title)
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(issue.message)
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let suggestion = issue.suggestion {
                        Text(suggestion)
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !issue.actions.isEmpty {
                actionRow(for: issue)
            }
        }
        .padding(CueInSpacing.md)
        .background(CueInColors.background.opacity(0.38), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func actionRow(for issue: ScheduleStartPreflightIssue) -> some View {
        HStack(spacing: CueInSpacing.sm) {
            ForEach(issue.actions) { action in
                Button {
                    handle(action)
                } label: {
                    Label(action.title, systemImage: action.icon)
                        .font(CueInTypography.micro)
                        .foregroundStyle(action.isDestructive ? CueInColors.danger : CueInColors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(action.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func metricTile(value: String, label: String, icon: String, tint: Color = CueInColors.textSecondary) -> some View {
        HStack(spacing: CueInSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(label)
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
            }
        }
        .padding(CueInSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CueInColors.surfaceSecondary.opacity(0.54), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var planningNote: some View {
        HStack(alignment: .top, spacing: CueInSpacing.sm) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CueInColors.textTertiary)
                .padding(.top, 2)

            Text("Schedule keeps block order, fills from Execution on start, then recalculates durations to land on your chosen end time.")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var startButton: some View {
        Button {
            onStart(max(draftScheduleEnd, minimumEnd))
        } label: {
            HStack {
                Label("Start run", systemImage: "play.fill")
                Spacer()
                Text(Self.timeLabel(max(draftScheduleEnd, minimumEnd)))
                    .monospacedDigit()
                    .foregroundStyle(CueInColors.background.opacity(0.58))
            }
            .font(CueInTypography.bodyMedium)
            .foregroundStyle(CueInColors.background)
            .padding(.horizontal, CueInSpacing.lg)
            .padding(.vertical, CueInSpacing.md)
            .background(CueInColors.textPrimary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(cannotStart)
        .opacity(cannotStart ? 0.45 : 1)
    }

    private var cancelButton: some View {
        Button("Cancel", role: .cancel, action: onCancel)
            .font(CueInTypography.body)
            .foregroundStyle(CueInColors.textSecondary)
            .frame(maxWidth: .infinity)
    }

    private func statChip(_ text: String) -> some View {
        Text(text)
            .font(CueInTypography.micro)
            .foregroundStyle(CueInColors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(CueInColors.surfaceTertiary.opacity(0.78), in: Capsule(style: .continuous))
    }

    private func handle(_ action: ScheduleStartPreflightAction) {
        if action == .useSafeEnd, let recommendedEnd = preview.recommendedMinimumEnd {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                draftScheduleEnd = recommendedEnd
            }
            return
        }

        onIssueAction(action)
    }

    private var headerTint: Color {
        if preview.hasBlockingIssues { return CueInColors.danger }
        if !preview.preflightIssues.isEmpty { return CueInColors.warning }
        return CueInColors.success
    }

    private var minimumEnd: Date {
        Date().addingTimeInterval(60)
    }

    private var cannotStart: Bool {
        draftScheduleEnd <= minimumEnd || preview.hasBlockingIssues || preview.blockCount == 0
    }

    private var windowLabel: String {
        let minutes = max(Int(draftScheduleEnd.timeIntervalSince(Date()) / 60), 0)
        return Self.durationLabel(minutes: minutes)
    }

    private static func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func durationLabel(minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60

        if hours > 0, remainder > 0 {
            return "\(hours)h \(remainder)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }
}

struct ScheduleStartPreview: Equatable {
    var blockCount: Int
    var routineBlockCount: Int
    var fillBlockCount: Int
    /// Blocks with `taskSource == .noTasks` (no checklist / no pool).
    var noTasksBlockCount: Int
    var pinnedBlockCount: Int = 0
    var openExecutionTaskCount: Int
    var priorityTaskCount: Int
    var nominalMinutes: Int
    var preflightIssues: [ScheduleStartPreflightIssue] = []
    var recommendedMinimumEnd: Date? = nil

    var hasBlockingIssues: Bool {
        preflightIssues.contains { $0.severity == .critical }
    }

    static let empty = ScheduleStartPreview(
        blockCount: 0,
        routineBlockCount: 0,
        fillBlockCount: 0,
        noTasksBlockCount: 0,
        openExecutionTaskCount: 0,
        priorityTaskCount: 0,
        nominalMinutes: 0
    )
}

struct ScheduleStartPreflightIssue: Identifiable, Equatable {
    enum Severity: String, Equatable {
        case critical
        case warning
        case notice

        var tint: Color {
            switch self {
            case .critical: return CueInColors.danger
            case .warning: return CueInColors.warning
            case .notice: return CueInColors.textTertiary
            }
        }

        var icon: String {
            switch self {
            case .critical: return "exclamationmark.triangle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .notice: return "info.circle.fill"
            }
        }
    }

    var id: String
    var severity: Severity
    var title: String
    var message: String
    var suggestion: String?
    var actions: [ScheduleStartPreflightAction] = []
}

enum ScheduleStartPreflightAction: Identifiable, Equatable {
    case useSafeEnd
    case unpinBlock(UUID)
    case deleteBlock(UUID)

    var id: String {
        switch self {
        case .useSafeEnd:
            return "use-safe-end"
        case .unpinBlock(let id):
            return "unpin-\(id.uuidString)"
        case .deleteBlock(let id):
            return "delete-\(id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .useSafeEnd: return "Use safe end"
        case .unpinBlock: return "Unpin"
        case .deleteBlock: return "Delete"
        }
    }

    var icon: String {
        switch self {
        case .useSafeEnd: return "wand.and.stars"
        case .unpinBlock: return "pin.slash.fill"
        case .deleteBlock: return "trash.fill"
        }
    }

    var isDestructive: Bool {
        if case .deleteBlock = self { return true }
        return false
    }

    var background: Color {
        isDestructive
            ? CueInColors.danger.opacity(0.14)
            : CueInColors.surfaceSecondary.opacity(0.72)
    }
}

#Preview {
    ScheduleStartSetupSheet(
        preview: ScheduleStartPreview(
            blockCount: 6,
            routineBlockCount: 2,
            fillBlockCount: 3,
            noTasksBlockCount: 1,
            openExecutionTaskCount: 12,
            priorityTaskCount: 4,
            nominalMinutes: 480
        ),
        draftScheduleEnd: .constant(Date().addingTimeInterval(8 * 3600)),
        onStart: { _ in },
        onIssueAction: { _ in },
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}
