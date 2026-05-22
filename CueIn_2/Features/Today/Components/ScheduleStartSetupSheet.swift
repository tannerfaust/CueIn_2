import SwiftUI

// MARK: - ScheduleStartSetupSheet
/// Preflight before a Schedule becomes a live run — kept minimal: one glance summary, end time, issues (if any), start.

struct ScheduleStartSetupSheet: View {
    let preview: ScheduleStartPreview
    @Binding var draftScheduleEnd: Date
    let onStart: (Date) -> Void
    let onIssueAction: (ScheduleStartPreflightAction) -> Void
    let onCancel: () -> Void

    private var sheetNavigationTitle: String {
        if preview.blockCount == 0 { return "No blocks" }
        if preview.hasBlockingIssues { return "Needs attention" }
        return "Start day"
    }

    var body: some View {
        CueInBottomSheet(title: sheetNavigationTitle, onDismiss: onCancel, toolbarDismissStyle: .closeLeading) {
            VStack(alignment: .leading, spacing: CueInSpacing.lg) {
                compactSummary
                endTimeCard
                statusOrIssues
                startButton
            }
            .padding(.bottom, CueInSpacing.md)
        }
    }

    // MARK: - Summary

    private var compactSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            if preview.blockCount == 0 {
                Text("Add blocks to your TimeMap before starting.")
                    .font(CueInTypography.body)
                    .foregroundStyle(CueInColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(preview.blockCount) blocks")
                    .font(CueInTypography.body)
                    .foregroundStyle(CueInColors.textPrimary)

                Text("Planned in blocks: \(Self.durationLabel(minutes: preview.nominalMinutes))")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if preview.pinnedBlockCount > 0 {
                    Text("\(preview.pinnedBlockCount) block\(preview.pinnedBlockCount == 1 ? "" : "s") use fixed clock times")
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - End time

    private var endTimeCard: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("TimeMap ends")
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(CueInColors.textSecondary)
                Spacer(minLength: 0)
                Text(runWindowSummary)
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }

            DatePicker(
                "End",
                selection: $draftScheduleEnd,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .tint(CueInColors.accentFocus)
        }
        .padding(CueInSpacing.md)
        .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(CueInColors.cardBorder.opacity(0.6), lineWidth: 0.5)
        }
    }

    // MARK: - Status / preflight

    @ViewBuilder
    private var statusOrIssues: some View {
        if preview.blockCount == 0 {
            EmptyView()
        } else if preview.preflightIssues.isEmpty {
            HStack(spacing: CueInSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CueInColors.success)
                Text("Nothing blocking this end time.")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: CueInSpacing.md) {
                ForEach(Array(preview.preflightIssues.enumerated()), id: \.element.id) { index, issue in
                    if index > 0 {
                        Divider()
                            .background(CueInColors.cardBorder.opacity(0.45))
                    }
                    preflightIssueBlock(issue)
                }

                if let recommendedEnd = preview.recommendedMinimumEnd,
                   recommendedEnd > draftScheduleEnd {
                    Button {
                        handle(.useSafeEnd)
                    } label: {
                        HStack {
                            Text("Use minimum end")
                                .font(CueInTypography.captionMedium)
                            Spacer(minLength: 0)
                            Text(Self.timeLabel(recommendedEnd))
                                .font(CueInTypography.captionMedium)
                                .monospacedDigit()
                        }
                        .foregroundStyle(CueInColors.accentFocus)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(CueInSpacing.md)
            .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(issueOutlineTint.opacity(0.35), lineWidth: 0.5)
            }
        }
    }

    private func preflightIssueBlock(_ issue: ScheduleStartPreflightIssue) -> some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            HStack(alignment: .top, spacing: CueInSpacing.sm) {
                Image(systemName: issue.severity.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(issue.severity.tint)
                    .frame(width: 20, alignment: .topLeading)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
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
                VStack(spacing: CueInSpacing.xs) {
                    ForEach(issue.actions) { action in
                        Button {
                            handle(action)
                        } label: {
                            HStack {
                                Label(action.title, systemImage: action.icon)
                                    .font(CueInTypography.captionMedium)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(action.isDestructive ? CueInColors.danger : CueInColors.textPrimary)
                            .padding(.horizontal, CueInSpacing.md)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                action.isDestructive
                                    ? CueInColors.danger.opacity(0.10)
                                    : CueInColors.surfaceSecondary.opacity(0.55),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Start

    private var startButton: some View {
        Button {
            onStart(max(draftScheduleEnd, minimumEnd))
        } label: {
            HStack {
                Text("Start")
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
                Text(Self.timeLabel(max(draftScheduleEnd, minimumEnd)))
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .opacity(0.85)
            }
            .font(CueInTypography.bodyMedium)
            .foregroundStyle(CueInColors.background)
            .padding(.horizontal, CueInSpacing.lg)
            .padding(.vertical, CueInSpacing.md + 2)
            .frame(maxWidth: .infinity)
            .background(
                cannotStart ? CueInColors.textTertiary : CueInColors.textPrimary,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(cannotStart)
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

    private var issueOutlineTint: Color {
        if preview.hasBlockingIssues { return CueInColors.danger }
        if !preview.preflightIssues.isEmpty { return CueInColors.warning }
        return CueInColors.cardBorder
    }

    private var minimumEnd: Date {
        Date().addingTimeInterval(60)
    }

    private var cannotStart: Bool {
        draftScheduleEnd <= minimumEnd || preview.hasBlockingIssues || preview.blockCount == 0
    }

    /// Calendar span from now until the chosen end (distinct from “planned in blocks” sum above).
    private var runWindowMinutes: Int {
        max(Int(draftScheduleEnd.timeIntervalSince(Date()) / 60), 0)
    }

    private var runWindowSummary: String {
        "Run window: \(Self.durationLabel(minutes: runWindowMinutes))"
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
    .cueInPreferredColorScheme()
}
