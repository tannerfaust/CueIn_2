import SwiftUI

struct TodayTodoRowReorderActions {
    let onBegan: (CGPoint) -> Void
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void
    let onCancelled: () -> Void
    let onTapped: () -> Void
}

// MARK: - TodayTodoTaskRow
/// Today “To-do view” row: layout and chrome follow ``TodayDisplayPreferences`` to‑do settings.

struct TodayTodoTaskRow: View {

    let task: TaskItem
    var store: TasksStore
    var onOpen: () -> Void
    var onDelete: () -> Void
    var allowsSwipe: Bool = true
    var reorderActions: TodayTodoRowReorderActions?

    @AppStorage(TodayDisplayPreferences.todoTaskBlockStyle) private var blockStyleRaw
        = TodayDisplayPreferences.TodoTaskBlockStyle.listClassic.rawValue
    @AppStorage(TodayDisplayPreferences.todoRowDensity) private var rowDensityRaw
        = TodayDisplayPreferences.TodoRowDensity.regular.rawValue

    @AppStorage(TodayDisplayPreferences.todoRowShowCheckbox) private var rowShowCheckbox = true
    @AppStorage(TodayDisplayPreferences.todoRowShowPriorityIcon) private var rowShowPriorityIcon = true
    @AppStorage(TodayDisplayPreferences.todoRowShowOverdueIcon) private var rowShowOverdueIcon = true
    @AppStorage(TodayDisplayPreferences.todoRowShowProjectOrFieldPill) private var rowShowProjectOrFieldPill = true
    @AppStorage(TodayDisplayPreferences.todoRowProjectOrFieldPillIconOnly) private var rowProjectOrFieldPillIconOnly = false
    @AppStorage(TodayDisplayPreferences.todoRowShowPlannedMinutes) private var rowShowPlannedMinutes = false
    @AppStorage(TodayDisplayPreferences.todoRowShowDueDate) private var rowShowDueDate = false
    @AppStorage(TodayDisplayPreferences.todoRowShowTags) private var rowShowTags = false
    @AppStorage(TodayDisplayPreferences.todoRowShowNotesPreview) private var rowShowNotesPreview = false
    @AppStorage(TodayDisplayPreferences.todoRowShowLeadingFieldAccent) private var rowShowLeadingFieldAccent = false

    @AppStorage(TodayDisplayPreferences.todoRowShowInProgressDetails) private var rowShowInProgressDetails = true
    @AppStorage(TodayDisplayPreferences.todoRowShowWorkTypeChip) private var rowShowWorkTypeChip = true
    @AppStorage(TodayDisplayPreferences.todoRowShowSubtasks) private var rowShowSubtasks = true

    @State private var dragOffset: CGFloat = 0
    @State private var hasCrossedThreshold = false
    @State private var isSwipeActive = false
    @State private var isStatusPopoverPresented = false
    @State private var isCompactStatusPopoverPresented = false
    @State private var swipeCompleteHaptic = false
    @State private var swipeThresholdHaptic = false

    private let completeThreshold: CGFloat = 80
    private let deleteRevealThreshold: CGFloat = -54
    private let deleteCommitThreshold: CGFloat = -152
    private let deleteActionWidth: CGFloat = 96
    private let maxSwipe: CGFloat = 184
    private let checkboxSize: CGFloat = 20

    private var blockStyle: TodayDisplayPreferences.TodoTaskBlockStyle {
        TodayDisplayPreferences.migratedTodoTaskBlockStyle(from: blockStyleRaw)
    }

    private var rowDensity: TodayDisplayPreferences.TodoRowDensity {
        TodayDisplayPreferences.migratedTodoRowDensity(from: rowDensityRaw)
    }

    private var rowVerticalPadding: CGFloat { rowDensity.verticalPadding }

    /// Frames wrap the row with their own outer padding — keep inner row a bit tighter so the list doesn’t feel vertically “compressed”.
    private var mainRowVerticalPadding: CGFloat {
        switch blockStyle {
        case .listClassic:
            return rowVerticalPadding
        case .frames:
            return max(3, rowVerticalPadding - 3)
        }
    }

    private var showsLeadingAccent: Bool {
        rowShowLeadingFieldAccent && fieldAccentColor != nil
    }

    private var fieldAccentColor: Color? {
        if let project = store.project(task.projectID) {
            return store.color(for: project)
        }
        if let field = store.field(task.fieldID) {
            return field.color
        }
        return nil
    }

    private var showsInProgressDetail: Bool {
        rowShowInProgressDetails && task.status == .active && !task.isCompleted
    }

    /// Whole task block (row + expansion) reads as “selected” while Doing.
    private var showsDoingSelectionHighlight: Bool {
        task.status == .active && !task.isCompleted
    }

    private var doingSelectionCornerRadius: CGFloat {
        switch blockStyle {
        case .listClassic:
            return CueInSpacing.md
        case .frames:
            return CueInSpacing.cardRadius
        }
    }

    private var expansionLeadingPadding: CGFloat {
        let base: CGFloat = rowShowCheckbox ? 34 : 6
        return base + (showsLeadingAccent ? 5 : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .center) {
                swipeBackground
                mainRow
                    .offset(x: dragOffset)
                    .simultaneousGesture(swipeGesture)
            }

            if showsInProgressDetail {
                inProgressExpansion
                    .padding(.top, 8)
                    .padding(.leading, expansionLeadingPadding)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, showsDoingSelectionHighlight ? CueInSpacing.xs : 0)
        .padding(.horizontal, showsDoingSelectionHighlight ? CueInSpacing.xs : 0)
        .background {
            if showsDoingSelectionHighlight {
                RoundedRectangle(cornerRadius: doingSelectionCornerRadius, style: .continuous)
                    .fill(CueInColors.surfaceSecondary.opacity(0.52))
            }
        }
        .overlay {
            if showsDoingSelectionHighlight {
                RoundedRectangle(cornerRadius: doingSelectionCornerRadius, style: .continuous)
                    .strokeBorder(CueInColors.divider.opacity(0.85), lineWidth: 0.5)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showsInProgressDetail)
        .animation(.easeInOut(duration: 0.2), value: showsDoingSelectionHighlight)
        .sensoryFeedback(.success, trigger: swipeCompleteHaptic)
        .sensoryFeedback(.impact(weight: .medium), trigger: swipeThresholdHaptic)
    }

    // MARK: Main row

    private var mainRow: some View {
        HStack(alignment: .top, spacing: 10) {
            if showsLeadingAccent, let accent = fieldAccentColor {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent.opacity(task.isCompleted ? 0.35 : 0.92))
                    .frame(width: 3)
                    .padding(.vertical, 2)
            }

            if rowShowCheckbox {
                statusMenuControl
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 8) {
                    Text(task.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(task.isCompleted ? CueInColors.textTertiary : CueInColors.textPrimary)
                        .strikethrough(task.isCompleted, color: CueInColors.textTertiary.opacity(0.55))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(0)

                    HStack(alignment: .center, spacing: 8) {
                        if rowShowPlannedMinutes, !task.isCompleted {
                            Text(Self.shortDurationLabel(task.plannedMinutes))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CueInColors.textSecondary.opacity(0.9))
                                .monospacedDigit()
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(CueInColors.surfacePrimary.opacity(0.55))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(CueInColors.cardBorder.opacity(0.6), lineWidth: 0.5)
                                )
                        }

                        priorityOrOverdueIcons

                        if !rowShowCheckbox {
                            statusMenuControlCompact
                        }

                        if rowShowProjectOrFieldPill {
                            projectOrFieldPill
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                }

                if rowShowDueDate, let due = task.dueDate {
                    Text(Self.dueDateLabel(due, isCompleted: task.isCompleted))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            task.isOverdue && !task.isCompleted
                                ? CueInColors.danger.opacity(0.88)
                                : CueInColors.textTertiary
                        )
                }

                if rowShowTags, !task.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(task.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(CueInColors.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(CueInColors.surfaceSecondary.opacity(0.9))
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(CueInColors.divider, lineWidth: 0.5)
                                    )
                            }
                        }
                    }
                }

                if rowShowNotesPreview, !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(Self.notesPreview(task.notes))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(CueInColors.textTertiary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpen() }
        }
        .padding(.vertical, mainRowVerticalPadding)
        .padding(.horizontal, horizontalPaddingForStyle)
        .overlay {
            if let reorderActions {
                reorderPressSurface(actions: reorderActions)
            }
        }
    }

    private func reorderPressSurface(actions: TodayTodoRowReorderActions) -> some View {
        let remindersLikeHoldDuration: TimeInterval = 0.42
        let stationaryHoldTolerance: CGFloat = 16

        return HStack(spacing: 0) {
            Color.clear
                .frame(width: rowShowCheckbox ? 38 : 0)

            LongPressDragView(
                onBegan: actions.onBegan,
                onChanged: actions.onChanged,
                onEnded: actions.onEnded,
                onCancelled: actions.onCancelled,
                onTapped: actions.onTapped,
                minimumPressDuration: remindersLikeHoldDuration,
                allowableMovement: stationaryHoldTolerance
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Color.clear
                .frame(width: rowShowCheckbox ? 0 : 40)
        }
        .contentShape(Rectangle())
    }

    private var horizontalPaddingForStyle: CGFloat {
        switch blockStyle {
        case .listClassic: return 2
        case .frames: return 2
        }
    }

    @ViewBuilder
    private var priorityOrOverdueIcons: some View {
        if task.isOverdue && !task.isCompleted && rowShowOverdueIcon {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CueInColors.danger.opacity(0.92))
        } else if task.priority != .normal && !task.isCompleted && rowShowPriorityIcon {
            todoPriorityGlyph(priority: task.priority)
        }
    }

    /// Warm flame chip so priority reads at a glance (distinct from overdue exclamation).
    private func todoPriorityGlyph(priority: TaskPriority) -> some View {
        Image(systemName: priority.icon)
            .font(.system(size: 12, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(priority.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                priority.color.opacity(0.22),
                                priority.color.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(priority.color.opacity(0.38), lineWidth: 0.5)
            }
            .accessibilityLabel("\(priority.label) priority")
    }

    // MARK: Checkbox → status menu

    private var statusMenuControl: some View {
        Button {
            isStatusPopoverPresented = true
        } label: {
            checkboxGlyph
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isStatusPopoverPresented) {
            CueInTaskStatusPopoverContent(selection: task.status) { applyStatusAndClose($0) }
        }
    }

    private var statusMenuControlCompact: some View {
        Button {
            isCompactStatusPopoverPresented = true
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(CueInColors.textSecondary.opacity(0.85))
                .frame(width: 28, height: 32)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isCompactStatusPopoverPresented) {
            CueInTaskStatusPopoverContent(selection: task.status) { applyStatusAndClose($0) }
        }
    }

    private var checkboxGlyph: some View {
        CueInTaskStatusCheckbox(
            isCompleted: task.isCompleted,
            workflowStatus: task.isCompleted ? nil : task.status,
            diameter: checkboxSize
        )
        // Top-align in the tap target so the ring lines up with the first title line (default centers in 32pt).
        .frame(width: 28, height: 32, alignment: .top)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: task.isCompleted)
        .animation(.easeInOut(duration: 0.18), value: task.status)
    }

    private func applyStatusAndClose(_ status: TaskStatus) {
        isStatusPopoverPresented = false
        isCompactStatusPopoverPresented = false
        applyStatus(status)
    }

    private func applyStatus(_ status: TaskStatus) {
        if task.isCompleted {
            guard status != .completed else { return }
        } else {
            guard task.status != status else { return }
        }

        let snapshot = task
        let wasOnOpenTodayList = !snapshot.isCompleted
            && snapshot.status != .archived
            && (snapshot.isScheduledToday || snapshot.status == .active || snapshot.status == .paused)

        store.setTodayTodoTaskStatus(id: task.id, status: status)
        TodayViewModel.shared.syncExecutionTimelineAfterExternalTaskEdit()

        if status == .inbox, wasOnOpenTodayList {
            CueInToastCenter.shared.show(
                icon: "tray.fill",
                title: "Moved to Inbox",
                message: snapshot.title,
                tint: Color(hex: 0x64A8FF)
            ) {
                store.updateTask(snapshot)
                TodayViewModel.shared.syncExecutionTimelineAfterExternalTaskEdit()
            }
        }
    }

    // MARK: Project / field pill

    @ViewBuilder
    private var projectOrFieldPill: some View {
        if let project = store.project(task.projectID) {
            CueInProjectAttributionPill(
                title: project.name,
                systemImage: project.resolvedIconSystemName,
                iconTint: projectAttributionIconTint(project: project),
                isMuted: task.isCompleted,
                showsLabel: !rowProjectOrFieldPillIconOnly
            )
        } else if let field = store.field(task.fieldID) {
            CueInProjectAttributionPill(
                title: field.name,
                systemImage: field.resolvedIconSystemName,
                iconTint: field.color,
                isMuted: task.isCompleted,
                showsLabel: !rowProjectOrFieldPillIconOnly
            )
        }
    }

    /// Full pill uses project/field palette; icon-only mode tints with the task’s field color when available.
    private func projectAttributionIconTint(project: Project) -> Color {
        if rowProjectOrFieldPillIconOnly {
            if let fid = task.fieldID, let f = store.field(fid) { return f.color }
            if let f = store.field(project.fieldID) { return f.color }
            return store.color(for: project)
        }
        return store.color(for: project)
    }

    // MARK: In-progress expansion

    private var inProgressExpansion: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                timelineCapsule(
                    icon: "clock",
                    text: Self.durationLabel(task.plannedMinutes)
                )
                if rowShowWorkTypeChip, let type = task.executionType {
                    timelineCapsule(
                        icon: type.icon,
                        text: type.shortLabel
                    )
                }
            }

            if rowShowSubtasks, !task.subtasks.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(task.subtasks) { sub in
                        subtaskLine(sub)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CueInColors.surfacePrimary.opacity(showsDoingSelectionHighlight ? 0.28 : 0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(CueInColors.cardBorder.opacity(0.45), lineWidth: 0.5)
                )
            }
        }
    }

    private func timelineCapsule(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CueInColors.textSecondary.opacity(0.88))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CueInColors.textSecondary.opacity(0.92))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(CueInColors.surfacePrimary.opacity(0.45))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(CueInColors.cardBorder.opacity(0.72), lineWidth: 0.5)
        )
    }

    private func subtaskLine(_ sub: TaskSubtask) -> some View {
        Button {
            store.toggleTodayTodoSubtask(taskID: task.id, subtaskID: sub.id)
            TodayViewModel.shared.syncExecutionTimelineAfterExternalTaskEdit()
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: sub.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(sub.isCompleted ? CueInColors.success : CueInColors.textTertiary)
                Text(sub.title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(sub.isCompleted ? CueInColors.textTertiary : CueInColors.textPrimary)
                    .strikethrough(sub.isCompleted, color: CueInColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: Swipe

    @ViewBuilder
    private var swipeBackground: some View {
        let rowMin: CGFloat = 44 + rowVerticalPadding * 2
        if dragOffset > 0 {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: task.isCompleted ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                    Text(task.isCompleted ? "Undo" : "Done")
                        .font(CueInTypography.captionMedium)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(task.isCompleted ? CueInColors.textSecondary : CueInColors.success)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    Capsule(style: .continuous)
                        .fill((task.isCompleted ? CueInColors.textTertiary : CueInColors.success).opacity(0.14))
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            (task.isCompleted ? CueInColors.textTertiary : CueInColors.success).opacity(0.28),
                            lineWidth: 0.5
                        )
                }

                Spacer(minLength: 0)
            }
            .opacity(min(1, dragOffset / completeThreshold))
            .padding(.leading, 14)
            .frame(minHeight: rowMin)
            .background(CueInColors.surfaceSecondary.opacity(0.36))
        } else if dragOffset < 0 {
            HStack {
                Spacer(minLength: 0)

                Button {
                    swipeCompleteHaptic.toggle()
                    onDelete()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        dragOffset = 0
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text("Delete")
                            .font(CueInTypography.captionMedium)
                            .fontWeight(.semibold)
                        Image(systemName: "trash.fill")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(CueInColors.danger)
                    .padding(.horizontal, 12)
                    .frame(width: deleteActionWidth - 14, height: 34)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CueInColors.danger.opacity(0.14))
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(CueInColors.danger.opacity(0.28), lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
            }
            .opacity(min(1, -dragOffset / abs(deleteRevealThreshold)))
            .padding(.trailing, 14)
            .frame(minHeight: rowMin)
            .background(CueInColors.surfaceSecondary.opacity(0.36))
        } else {
            Color.clear
                .frame(minHeight: rowMin)
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard allowsSwipe else { return }
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)

                if !isSwipeActive {
                    guard horizontal > vertical * 1.35 else { return }
                    isSwipeActive = true
                }

                let raw = value.translation.width
                let bound: CGFloat = raw > 0 ? min(raw, maxSwipe) : max(raw, -maxSwipe)
                dragOffset = bound
                let past = raw > completeThreshold || raw < deleteCommitThreshold
                if past != hasCrossedThreshold {
                    hasCrossedThreshold = past
                    if past { swipeThresholdHaptic.toggle() }
                }
            }
            .onEnded { value in
                guard allowsSwipe, isSwipeActive else {
                    isSwipeActive = false
                    hasCrossedThreshold = false
                    return
                }
                let w = value.translation.width
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                if w > completeThreshold, horizontal > vertical * 1.2 {
                    swipeCompleteHaptic.toggle()
                    store.toggleComplete(task.id)
                    TodayViewModel.shared.syncExecutionTimelineAfterExternalTaskEdit()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        dragOffset = 0
                    }
                } else if w < deleteCommitThreshold, horizontal > vertical * 1.2 {
                    swipeCompleteHaptic.toggle()
                    onDelete()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        dragOffset = 0
                    }
                } else if w < deleteRevealThreshold, horizontal > vertical * 1.2 {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                        dragOffset = -deleteActionWidth
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        dragOffset = 0
                    }
                }
                isSwipeActive = false
                hasCrossedThreshold = false
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

    private static func shortDurationLabel(_ minutes: Int) -> String {
        durationLabel(minutes)
    }

    private static func notesPreview(_ notes: String) -> String {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? trimmed
        if firstLine.count <= 100 { return firstLine }
        return String(firstLine.prefix(97)) + "…"
    }

    private static func dueDateLabel(_ date: Date, isCompleted: Bool) -> String {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let dueDay = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: start, to: dueDay).day ?? 0
        let formatted = date.formatted(date: .abbreviated, time: .omitted)
        if cal.isDateInToday(date) {
            return isCompleted ? "Due date was today" : "Due today"
        }
        if days == 1 { return "Due tomorrow" }
        if days == -1 { return "Due yesterday" }
        if days > 1 { return "Due \(formatted)" }
        if days < -1 { return isCompleted ? "Was due \(formatted)" : "Overdue · \(formatted)" }
        return "Due \(formatted)"
    }
}
