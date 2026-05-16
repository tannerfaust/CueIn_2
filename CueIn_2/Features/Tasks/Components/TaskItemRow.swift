import SwiftUI

// MARK: - TaskItemRow
/// Minimal task row for task lists and today's execution pool.
///
/// Interactions:
/// • Tap body          → open detail (`onOpen`)
/// • Tap status circle → status/action menu
/// • Swipe right       → quick complete
/// • Swipe left        → quick actions
/// • Long-press        → context menu

struct TaskItemRow: View {

    let task: TaskItem
    let store: TasksStore

    let onToggle: () -> Void
    let onOpen: () -> Void
    var onDelete: () -> Void = {}
    var onSchedule: (Date?) -> Void = { _ in }
    var onMoreActions: () -> Void = {}

    /// Retained for call-site compatibility; layout is always the flat list style.
    var compactStyle: Bool = false
    var isQueuedForToday: Bool = false
    var onQueueToday: (() -> Void)? = nil

    @State private var dragOffset: CGFloat = 0
    @State private var hasCrossedThreshold = false
    @State private var isStatusPopoverPresented = false

    @State private var completeHaptic = false
    @State private var thresholdHaptic = false
    @State private var selectHaptic = false
    @State private var queueTapHaptic = false

    private let completeThreshold: CGFloat = 80
    private let moreActionsThreshold: CGFloat = -90
    private let maxSwipe: CGFloat = 140
    private let checkboxSize: CGFloat = 18
    @AppStorage(TasksTaskDisplayPrefs.densityKey) private var densityRaw = TasksDisplayDensity.compact.rawValue
    @AppStorage(TasksTaskDisplayPrefs.metadataKey) private var metadataRaw = TasksMetadataLevel.balanced.rawValue
    @AppStorage(TasksTaskDisplayPrefs.showProjectKey) private var showProject = true
    @AppStorage(TasksTaskDisplayPrefs.showDueKey) private var showDue = true
    @AppStorage(TasksTaskDisplayPrefs.showEstimateKey) private var showEstimate = true
    @AppStorage(TasksTaskDisplayPrefs.showPriorityKey) private var showPriority = true

    private var density: TasksDisplayDensity {
        TasksDisplayDensity(rawValue: densityRaw) ?? .compact
    }

    private var metadataLevel: TasksMetadataLevel {
        TasksMetadataLevel(rawValue: metadataRaw) ?? .balanced
    }

    var body: some View {
        ZStack(alignment: .center) {
            swipeBackground
            foreground
                .offset(x: dragOffset)
                .gesture(swipeGesture)
                .contextMenu { contextMenuContent }
        }
        .sensoryFeedback(.success, trigger: completeHaptic)
        .sensoryFeedback(.impact(weight: .medium), trigger: thresholdHaptic)
        .sensoryFeedback(.selection, trigger: selectHaptic)
        .sensoryFeedback(.impact(weight: .light), trigger: queueTapHaptic)
    }

    // MARK: Foreground

    private var foreground: some View {
        HStack(alignment: .center, spacing: 10) {
            checkbox

            VStack(alignment: .leading, spacing: 3) {
                titleLine
                if metadataLevel != .minimal, !metaSummary.isEmpty {
                    metaLine
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onOpen() }

            if showProject && metadataLevel != .minimal {
                projectPill
            }

            if onQueueToday != nil {
                queueTodayControl
            }
        }
        .padding(.vertical, density.rowVerticalPadding)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.clear)
        .contentShape(Rectangle())
    }

    // MARK: Title

    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(task.title)
                .font(.system(size: density.titleFontSize, weight: .medium))
                .foregroundStyle(task.isCompleted ? CueInColors.textTertiary : CueInColors.textPrimary)
                .strikethrough(task.isCompleted, color: CueInColors.textTertiary.opacity(0.55))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if task.isOverdue {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CueInColors.danger.opacity(0.9))
            } else if task.priority != .normal && showPriority {
                Image(systemName: task.priority.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(task.priority.color.opacity(0.9))
            }
        }
    }

    // MARK: Metadata

    private var metaLine: some View {
        Text(metaSummary)
        .font(.system(size: density.metaFontSize, weight: .regular))
        .foregroundStyle(CueInColors.textTertiary.opacity(metaForegroundOpacity))
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }

    private var metaForegroundOpacity: Double {
        task.isCompleted ? 0.5 : 0.92
    }

    private var metaSummary: String {
        var parts: [String] = []
        if showDue, let date = dateLabel { parts.append(date) }
        if showEstimate { parts.append(Self.durationLabel(task.plannedMinutes)) }
        if metadataLevel == .full, let type = task.executionType { parts.append(type.shortLabel) }
        if metadataLevel == .full, task.recurrence != .none { parts.append("Repeats") }
        if metadataLevel == .full, !task.tags.isEmpty { parts.append("#\(task.tags[0])") }
        if metadataLevel == .full, !task.subtasks.isEmpty {
            parts.append("\(task.subtasks.filter(\.isCompleted).count)/\(task.subtasks.count) sub")
        }
        return parts.joined(separator: "  ·  ")
    }

    private var dateLabel: String? {
        if task.isCompleted { return "Done" }
        if task.status == .paused { return "Paused" }
        if task.isOverdue { return "Overdue" }
        if let due = task.dueDate {
            guard let label = Self.shortDateLabel(due) else { return nil }
            return "Due \(label)"
        }
        if let scheduled = task.scheduledDate {
            return Self.shortDateLabel(scheduled)
        }
        if task.status == .inbox { return "Inbox" }
        if task.status == .archived { return "Archived" }
        return nil
    }

    // MARK: Project

    @ViewBuilder
    private var projectPill: some View {
        if let project = store.project(task.projectID) {
            CueInProjectAttributionPill(
                title: project.name,
                systemImage: project.resolvedIconSystemName,
                iconTint: projectIconColor,
                isMuted: task.isCompleted
            )
        }
    }

    private var projectIconColor: Color {
        store.field(task.fieldID).map(\.color) ?? store.color(for: task)
    }

    // MARK: Checkbox

    private var checkbox: some View {
        Button {
            selectHaptic.toggle()
            isStatusPopoverPresented = true
        } label: {
            CueInTaskStatusCheckbox(
                isCompleted: task.isCompleted,
                workflowStatus: task.isCompleted ? nil : task.status,
                diameter: checkboxSize
            )
            .frame(width: 28, height: 32, alignment: .top)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.15), value: task.isCompleted)
            .animation(.easeInOut(duration: 0.18), value: task.status)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isStatusPopoverPresented) {
            CueInTaskStatusPopoverContent(selection: task.status) { status in
                store.setTodayTodoTaskStatus(id: task.id, status: status)
                isStatusPopoverPresented = false
            }
        }
    }

    // MARK: Queue today

    @ViewBuilder
    private var queueTodayControl: some View {
        if let onQueue = onQueueToday {
            Button {
                guard !task.isCompleted else { return }
                queueTapHaptic.toggle()
                onQueue()
            } label: {
                Image(systemName: isQueuedForToday ? "bolt.fill" : "bolt")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(queueBoltForeground)
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(task.isCompleted)
            .opacity(task.isCompleted ? 0.35 : 1)
            .accessibilityLabel(
                isQueuedForToday ? "Remove from execution pool" : "Add to execution pool"
            )
        }
    }

    private var queueBoltForeground: Color {
        if task.isCompleted { return CueInColors.textTertiary.opacity(0.35) }
        if isQueuedForToday { return CueInColors.accentFixed }
        return CueInColors.textTertiary.opacity(0.48)
    }

    // MARK: Swipe background

    @ViewBuilder
    private var swipeBackground: some View {
        let rowMin: CGFloat = 56
        if dragOffset > 0 {
            HStack(spacing: 6) {
                Image(systemName: task.isCompleted
                      ? "arrow.uturn.backward.circle.fill"
                      : "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                Text(task.isCompleted ? "Undo" : "Done")
                    .font(CueInTypography.captionMedium)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .opacity(min(1, dragOffset / completeThreshold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 28)
            .frame(minHeight: rowMin)
            .background(
                (task.isCompleted ? CueInColors.textTertiary : CueInColors.success)
                    .opacity(min(1, dragOffset / completeThreshold))
            )
        } else if dragOffset < 0 {
            HStack(spacing: 6) {
                Text("More")
                    .font(CueInTypography.captionMedium)
                    .fontWeight(.semibold)
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(CueInColors.textPrimary)
            .opacity(min(1, -dragOffset / abs(moreActionsThreshold)))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 28)
            .frame(minHeight: rowMin)
            .background(
                CueInColors.surfaceTertiary.opacity(min(1, -dragOffset / abs(moreActionsThreshold)))
            )
        }
    }

    private static func durationLabel(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
        }
        return "\(minutes)m"
    }

    private static func shortDateLabel(_ date: Date) -> String? {
        if Calendar.current.isDateInToday(date) { return nil }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                let raw = value.translation.width
                let bound: CGFloat = raw > 0
                    ? min(raw, maxSwipe)
                    : max(raw, -maxSwipe)
                dragOffset = bound

                let past = raw > completeThreshold || raw < moreActionsThreshold
                if past != hasCrossedThreshold {
                    hasCrossedThreshold = past
                    if past { thresholdHaptic.toggle() }
                }
            }
            .onEnded { value in
                let w = value.translation.width
                let crossedRight = w > completeThreshold
                let crossedLeft = w < moreActionsThreshold

                if crossedRight {
                    completeHaptic.toggle()
                    onToggle()
                } else if crossedLeft {
                    selectHaptic.toggle()
                    onMoreActions()
                }

                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    dragOffset = 0
                }
                hasCrossedThreshold = false
            }
    }

    // MARK: Context menu

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            completeHaptic.toggle()
            onToggle()
        } label: {
            Label(task.isCompleted ? "Mark incomplete" : "Mark complete",
                  systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark.circle")
        }

        Button {
            selectHaptic.toggle()
            onOpen()
        } label: {
            Label("Edit…", systemImage: "pencil")
        }

        Menu {
            Button {
                selectHaptic.toggle()
                onSchedule(Calendar.current.startOfDay(for: Date()))
            } label: { Label("Today", systemImage: "sun.max") }

            Button {
                selectHaptic.toggle()
                onSchedule(Calendar.current.date(
                    byAdding: .day,
                    value: 1,
                    to: Calendar.current.startOfDay(for: Date())
                ))
            } label: { Label("Tomorrow", systemImage: "arrow.turn.up.right") }

            Button {
                selectHaptic.toggle()
                onSchedule(Calendar.current.date(
                    byAdding: .day,
                    value: 7,
                    to: Calendar.current.startOfDay(for: Date())
                ))
            } label: { Label("Next week", systemImage: "calendar") }

            Divider()

            Button {
                selectHaptic.toggle()
                onSchedule(nil)
            } label: { Label("Move to Inbox", systemImage: "tray") }
        } label: {
            Label("Schedule", systemImage: "calendar")
        }

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
