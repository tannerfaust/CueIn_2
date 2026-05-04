import SwiftUI

// MARK: - TaskItemRow
/// Minimal task row for task lists and today's execution pool.
///
/// Interactions:
/// • Tap body          → open detail (`onOpen`)
/// • Tap checkbox      → toggle complete (`onToggle`) with success haptic
/// • Swipe right       → quick complete
/// • Swipe left        → delete
/// • Long-press        → context menu

struct TaskItemRow: View {

    let task: TaskItem
    let store: TasksStore

    let onToggle: () -> Void
    let onOpen: () -> Void
    var onDelete: () -> Void = {}
    var onSchedule: (Date?) -> Void = { _ in }

    /// Retained for call-site compatibility; layout is always the flat list style.
    var compactStyle: Bool = false
    var isQueuedForToday: Bool = false
    var onQueueToday: (() -> Void)? = nil

    @State private var dragOffset: CGFloat = 0
    @State private var hasCrossedThreshold = false

    @State private var completeHaptic = false
    @State private var thresholdHaptic = false
    @State private var selectHaptic = false
    @State private var queueTapHaptic = false

    private let completeThreshold: CGFloat = 80
    private let deleteThreshold: CGFloat = -90
    private let maxSwipe: CGFloat = 140
    private let checkboxSize: CGFloat = 18

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
                metaLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onOpen() }

            projectPill

            if onQueueToday != nil {
                queueTodayControl
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.clear)
        .contentShape(Rectangle())
    }

    // MARK: Title

    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(task.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(task.isCompleted ? CueInColors.textTertiary : CueInColors.textPrimary)
                .strikethrough(task.isCompleted, color: CueInColors.textTertiary.opacity(0.55))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if task.isOverdue {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CueInColors.danger.opacity(0.9))
            } else if task.priority != .normal {
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
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(CueInColors.textTertiary.opacity(metaForegroundOpacity))
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }

    private var metaForegroundOpacity: Double {
        task.isCompleted ? 0.5 : 0.92
    }

    private var metaSummary: String {
        var parts: [String] = []
        if let date = dateLabel { parts.append(date) }
        parts.append(Self.durationLabel(task.plannedMinutes))
        if let type = task.executionType { parts.append(type.shortLabel) }
        if task.recurrence != .none { parts.append("Repeats") }
        if !task.tags.isEmpty { parts.append("#\(task.tags[0])") }
        if !task.subtasks.isEmpty {
            parts.append("\(task.subtasks.filter(\.isCompleted).count)/\(task.subtasks.count) sub")
        }
        return parts.joined(separator: "  ·  ")
    }

    private var dateLabel: String? {
        if task.isCompleted { return "Done" }
        if task.status == .active { return "Doing" }
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
            completeHaptic.toggle()
            onToggle()
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
                Text("Delete")
                    .font(CueInTypography.captionMedium)
                    .fontWeight(.semibold)
                Image(systemName: "trash.fill")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .opacity(min(1, -dragOffset / abs(deleteThreshold)))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 28)
            .frame(minHeight: rowMin)
            .background(
                CueInColors.danger.opacity(min(1, -dragOffset / abs(deleteThreshold)))
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

                let past = raw > completeThreshold || raw < deleteThreshold
                if past != hasCrossedThreshold {
                    hasCrossedThreshold = past
                    if past { thresholdHaptic.toggle() }
                }
            }
            .onEnded { value in
                let w = value.translation.width
                let crossedRight = w > completeThreshold
                let crossedLeft = w < deleteThreshold

                if crossedRight {
                    completeHaptic.toggle()
                    onToggle()
                } else if crossedLeft {
                    onDelete()
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
        .menuStyle(.borderlessButton)
        .cueInMenuInteractionStability()

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
