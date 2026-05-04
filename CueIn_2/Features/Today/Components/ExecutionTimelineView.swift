import SwiftUI
import UIKit

// MARK: - ExecutionTimelineView
/// A **vertical time-axis calendar** of the day — Motion-style.
///
/// Every task sits at an absolute Y position based on its `startDate`, with height
/// proportional to its duration. Dragging a task vertically moves it in time; on
/// drop, the `ExecutionReflow` strategy in the view model decides how following
/// tasks cascade. Fixed tasks are anchors.
///
/// The Schedule tab is the *planning surface*. This is the *running surface* —
/// what is happening on the clock, right now, with room to adjust in flight.

struct ExecutionTimelineView: View {
    let days: [ExecutionDayPlan]
    let currentTime: Date
    /// Points per hour — controlled by the user's scale preference.
    let hourHeight: CGFloat
    /// Set to `false` when this view is embedded inside a container that already
    /// shows a day header (e.g. `PagedExecutionTimelineView`).
    var showDayHeaders: Bool = true
    let onToggleTask: (Date, UUID) -> Void
    let onDeleteTask: (Date, UUID) -> Void
    let onEditTask: (Date, ExecutionTaskCard) -> Void
    let onPreviewMoveTask: (Date, UUID, Date) -> [ExecutionTaskCard]
    let onMoveTask: (Date, UUID, Date) -> Void

    /// Left gutter width used for hour labels and the NOW pill.
    static let timeGutter: CGFloat = 52
    /// Snap grid for drag interactions (minutes).
    static let snapMinutes: Int = 5
    /// Minimum visible hour range when the day has no tasks.
    static let defaultStartHour: Int = 6
    static let defaultEndHour: Int = 22

    @State private var hasPerformedInitialScroll = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(days) { day in
                        Section {
                            DayCalendarSection(
                                day: day,
                                currentTime: currentTime,
                                hourHeight: hourHeight,
                                timeGutter: Self.timeGutter,
                                onToggleTask: { onToggleTask(day.id, $0) },
                                onDeleteTask: { onDeleteTask(day.id, $0) },
                                onEditTask: { onEditTask(day.id, $0) },
                                onPreviewMoveTask: { taskID, proposed in
                                    onPreviewMoveTask(day.id, taskID, proposed)
                                },
                                onMoveTask: { taskID, proposed in
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                        onMoveTask(day.id, taskID, proposed)
                                    }
                                }
                            )
                            .padding(.horizontal, CueInSpacing.screenHorizontal)
                            .padding(.bottom, CueInSpacing.xxl)
                            .id(day.id)
                        } header: {
                            executionDayHeader(day: day)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.top, CueInSpacing.md)
                .padding(.bottom, CueInLayout.scrollBottomInset)
            }
            .task {
                guard !hasPerformedInitialScroll else { return }
                hasPerformedInitialScroll = true
                try? await Task.sleep(nanoseconds: 120_000_000)
                scrollToNow(proxy: proxy, animated: false)
            }
            .onChange(of: hourHeight) {
                scrollToNow(proxy: proxy, animated: true)
            }
        }
    }

    private func scrollToNow(proxy: ScrollViewProxy, animated: Bool) {
        guard let todayID = days
            .first(where: { Calendar.current.isDate($0.date, inSameDayAs: currentTime) })?
            .id ?? days.first?.id else { return }
        let cal = Calendar.current
        var targetHour = 7
        if cal.isDate(todayID, inSameDayAs: currentTime) {
            targetHour = max(0, cal.component(.hour, from: currentTime) - 1)
        } else if let firstTask = days.first(where: { $0.id == todayID })?.tasks.first {
            targetHour = max(0, cal.component(.hour, from: firstTask.startDate) - 1)
        }
        let anchor = HourGridView.anchorID(forHour: targetHour, dayID: todayID)
        if animated {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) {
                proxy.scrollTo(anchor, anchor: .top)
            }
        } else {
            withAnimation(.easeInOut(duration: 0.4)) {
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
    }

    @ViewBuilder
    private func executionDayHeader(day: ExecutionDayPlan) -> some View {
        if showDayHeaders {
            ExecutionCalendarDayTitle(dayStart: day.date, relativeNow: currentTime)
        }
    }
}

// MARK: - Execution calendar day title (glass pill + hairline)

/// Sticky day header: a liquid-glass capsule pinned to the left of a full-width hairline.
/// Relative names ("Today", "Tomorrow") prefix the date for the first two days;
/// everything beyond that shows weekday + day + month only.
private struct ExecutionCalendarDayTitle: View {
    let dayStart: Date
    let relativeNow: Date

    // MARK: Relative semantics

    private var cal: Calendar { .current }

    private var isToday: Bool {
        cal.isDate(dayStart, inSameDayAs: relativeNow)
    }

    private var isTomorrow: Bool {
        guard let tomorrow = cal.date(byAdding: .day, value: 1,
                                      to: cal.startOfDay(for: relativeNow)) else { return false }
        return cal.isDate(dayStart, inSameDayAs: tomorrow)
    }

    private var isYesterday: Bool {
        guard let yesterday = cal.date(byAdding: .day, value: -1,
                                       to: cal.startOfDay(for: relativeNow)) else { return false }
        return cal.isDate(dayStart, inSameDayAs: yesterday)
    }

    /// "Today", "Tomorrow", "Yesterday", or nil for anything else.
    private var relativeName: String? {
        if isToday      { return "Today" }
        if isTomorrow   { return "Tomorrow" }
        if isYesterday  { return "Yesterday" }
        return nil
    }

    // MARK: Date string

    private var dateString: String {
        let refYear = cal.component(.year, from: relativeNow)
        let dayYear = cal.component(.year, from: dayStart)
        if dayYear != refYear {
            return dayStart.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        }
        return dayStart.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .leading) {
            // Full-width hairline — sits at vertical mid-point of the strip.
            Rectangle()
                .fill(Color.white.opacity(isToday ? 0.16 : 0.09))
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)

            // Glass capsule floats on top of the wire — no block background.
            pillLabel
                .padding(.leading, CueInSpacing.screenHorizontal)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 36)
    }

    // MARK: Pill

    @ViewBuilder
    private var pillLabel: some View {
        Group {
            if let relative = relativeName {
                HStack(spacing: 0) {
                    Text(relative)
                        .foregroundStyle(isToday ? CueInColors.accentFocus : CueInColors.textPrimary)
                    Text("  ·  \(dateString)")
                        .foregroundStyle(CueInColors.textTertiary)
                }
            } else {
                Text(dateString)
                    .foregroundStyle(CueInColors.textSecondary)
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .modifier(DayPillGlassModifier(isToday: isToday))
    }
}

// MARK: - Glass modifier for the day pill

private struct DayPillGlassModifier: ViewModifier {
    let isToday: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(isToday
                        ? CueInColors.accentFocus.opacity(0.10)
                        : Color.white.opacity(0.06)
                    ),
                    in: .capsule
                )
        } else {
            content
                .background(
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isToday
                                ? CueInColors.accentFocus.opacity(0.35)
                                : Color.white.opacity(0.12),
                            lineWidth: 0.5
                        )
                }
        }
    }
}

// MARK: - DayCalendarSection

private struct DayCalendarSection: View {
    let day: ExecutionDayPlan
    let currentTime: Date
    let hourHeight: CGFloat
    let timeGutter: CGFloat
    let onToggleTask: (UUID) -> Void
    let onDeleteTask: (UUID) -> Void
    let onEditTask: (ExecutionTaskCard) -> Void
    let onPreviewMoveTask: (UUID, Date) -> [ExecutionTaskCard]
    let onMoveTask: (UUID, Date) -> Void

    @State private var previewTasks: [ExecutionTaskCard]?
    @State private var previewingTaskID: UUID?

    private var isToday: Bool { Calendar.current.isDate(day.date, inSameDayAs: currentTime) }
    private var displayTasks: [ExecutionTaskCard] { previewTasks ?? day.tasks }

    /// Trimmed hour window: spans from the earliest task (or 06:00) to the latest
    /// task end (or 22:00). Keeps the canvas compact instead of always 24h tall.
    private var visibleHourRange: (startHour: Int, endHour: Int) {
        let cal = Calendar.current
        var startHour = ExecutionTimelineView.defaultStartHour
        var endHour = ExecutionTimelineView.defaultEndHour

        if !displayTasks.isEmpty {
            var minStart = displayTasks[0].startDate
            var maxEnd = displayTasks[0].endDate
            if displayTasks.count > 1 {
                for i in 1..<displayTasks.count {
                    let t = displayTasks[i]
                    if t.startDate < minStart { minStart = t.startDate }
                    if t.endDate > maxEnd { maxEnd = t.endDate }
                }
            }
            let h0 = cal.component(.hour, from: minStart)
            startHour = min(startHour, max(0, h0 - 1))
            let h1 = cal.component(.hour, from: maxEnd)
            let m1 = cal.component(.minute, from: maxEnd)
            let rounded = m1 > 0 ? h1 + 1 : h1
            endHour = max(endHour, min(24, rounded + 1))
        }
        // Always allow the NOW line to be inside the window.
        if isToday {
            let h = cal.component(.hour, from: currentTime)
            startHour = min(startHour, max(0, h - 1))
            endHour = max(endHour, min(24, h + 2))
        }
        return (startHour, endHour)
    }

    private var canvasStart: Date {
        Calendar.current.date(bySettingHour: visibleHourRange.startHour, minute: 0, second: 0, of: day.date) ?? day.date
    }

    private var hourCount: Int { visibleHourRange.endHour - visibleHourRange.startHour }
    private var canvasHeight: CGFloat { hourHeight * CGFloat(hourCount) }

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            ZStack(alignment: .topLeading) {
                HourGridView(
                    startHour: visibleHourRange.startHour,
                    hourCount: hourCount,
                    hourHeight: hourHeight,
                    timeGutter: timeGutter,
                    dayID: day.id
                )

                ForEach(displayTasks) { task in
                    MotionTaskCard(
                        task: task,
                        canvasStart: canvasStart,
                        hourHeight: hourHeight,
                        timeGutter: timeGutter,
                        canvasHeight: canvasHeight,
                        isCurrent: isTaskCurrent(task),
                        onToggle: {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                onToggleTask(task.id)
                            }
                        },
                        onDelete: {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                onDeleteTask(task.id)
                            }
                        },
                        onEdit: {
                            onEditTask(task)
                        },
                        onPreviewMove: { proposedStart in
                            previewingTaskID = task.id
                            withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.88)) {
                                previewTasks = onPreviewMoveTask(task.id, proposedStart)
                            }
                        },
                        onMove: { proposedStart in
                            previewingTaskID = nil
                            previewTasks = nil
                            onMoveTask(task.id, proposedStart)
                        }
                    )
                }
                .animation(.spring(response: 0.48, dampingFraction: 0.86), value: layoutSignature)

                if isToday {
                    NowLineOverlay(
                        now: currentTime,
                        canvasStart: canvasStart,
                        hourHeight: hourHeight,
                        timeGutter: timeGutter
                    )
                }
            }
            .frame(height: canvasHeight)
        }
        .onChange(of: day.taskLayoutFingerprint) { _, _ in
            guard previewingTaskID == nil else { return }
            previewTasks = nil
        }
    }

    private var layoutSignature: String {
        displayTasks
            .sorted { $0.startDate < $1.startDate }
            .map { "\($0.id.uuidString.prefix(6))\(Int($0.startDate.timeIntervalSinceReferenceDate))\($0.durationMinutes)\($0.isCompleted ? 1 : 0)" }
            .joined(separator: ",")
    }

    private func isTaskCurrent(_ task: ExecutionTaskCard) -> Bool {
        isToday && currentTime >= task.startDate && currentTime < task.endDate && !task.isCompleted
    }

    private func yFor(date: Date) -> CGFloat {
        let minutes = Calendar.current.dateComponents([.minute], from: canvasStart, to: date).minute ?? 0
        return CGFloat(max(minutes, 0)) / 60 * hourHeight
    }
}

// MARK: - HourGridView
/// Grid drawn as a real VStack of fixed-height hour cells. Each cell gets an ID
/// so the ScrollViewReader can `scrollTo` a specific hour (used for "scroll to
/// now" on first appearance).

private struct HourGridView: View {
    let startHour: Int
    let hourCount: Int
    let hourHeight: CGFloat
    let timeGutter: CGFloat
    let dayID: Date

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<hourCount, id: \.self) { i in
                HourRow(
                    hour: startHour + i,
                    hourHeight: hourHeight,
                    timeGutter: timeGutter
                )
                .frame(height: hourHeight)
                .id(anchorID(forHour: startHour + i))
            }
        }
        .allowsHitTesting(false)
    }

    static func anchorID(forHour hour: Int, dayID: Date) -> String {
        "timeline-hour-\(Int(dayID.timeIntervalSince1970))-\(hour)"
    }

    private func anchorID(forHour hour: Int) -> String {
        Self.anchorID(forHour: hour, dayID: dayID)
    }
}

private struct HourRow: View {
    let hour: Int
    let hourHeight: CGFloat
    let timeGutter: CGFloat

    /// 00, 06, 12, 18 — strongly delineated key hours.
    private var isKeyHour: Bool { hour.isMultiple(of: 6) }
    /// 03, 09, 15, 21 — medium emphasis.
    private var isMidHour: Bool { !isKeyHour && hour.isMultiple(of: 3) }

    private var hourLabel: String { String(format: "%02d", hour % 24) }

    private var labelSize: CGFloat  { isKeyHour ? 12 : 10 }
    private var labelWeight: Font.Weight { isKeyHour ? .semibold : .regular }
    private var labelColor: Color {
        isKeyHour ? CueInColors.textSecondary
            : isMidHour ? CueInColors.textTertiary.opacity(0.75)
            : CueInColors.textTertiary.opacity(0.45)
    }
    private var lineOpacity: Double {
        isKeyHour ? 0.18 : isMidHour ? 0.11 : 0.07
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Hour label in gutter
            Text(hourLabel)
                .font(.system(size: labelSize, weight: labelWeight, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(labelColor)
                .frame(width: timeGutter - 10, alignment: .trailing)
                .padding(.trailing, 10)
                .offset(y: -6)

            // Grid lines column: full-hour at top, half-hour at midpoint
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.white.opacity(lineOpacity))
                    .frame(height: 0.5)

                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 0.5)
                    .offset(y: hourHeight / 2)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - NowLineOverlay

private struct NowLineOverlay: View {
    let now: Date
    let canvasStart: Date
    let hourHeight: CGFloat
    let timeGutter: CGFloat

    /// Crisp “now” indicator — white line, almost no bloom so it stays readable on dark tasks.
    private var lineColor: Color { Color.white.opacity(0.92) }

    var body: some View {
        GeometryReader { proxy in
            let y = yOffset()
            let gutterInset: CGFloat = 6
            let trackWidth = max(proxy.size.width - timeGutter - 4, 40)

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(lineColor)
                    .frame(width: trackWidth, height: 1.25)
                    .shadow(color: Color.black.opacity(0.45), radius: 1.5, y: 0.5)
                    .offset(x: timeGutter, y: y - 0.5)

                Circle()
                    .fill(lineColor)
                    .frame(width: 7, height: 7)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5)
                    }
                    .offset(x: timeGutter - 3.5, y: y - 3.5)

                Text(CueInTimeFormat.hourMinute(now))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CueInColors.textPrimary.opacity(0.95))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .modifier(NowPillGlassModifier())
                    .offset(x: gutterInset, y: y - 11)
            }
        }
        .allowsHitTesting(false)
    }

    private func yOffset() -> CGFloat {
        let minutes = Calendar.current.dateComponents([.minute], from: canvasStart, to: now).minute ?? 0
        return CGFloat(max(minutes, 0)) / 60 * hourHeight
    }

}

// MARK: - MotionTaskCard
/// A task card positioned absolutely on the day canvas. Height = duration.
/// Drag it vertically to reschedule; the view model's reflow decides how other
/// tasks respond on release.

private struct MotionTaskCard: View {
    let task: ExecutionTaskCard
    let canvasStart: Date
    let hourHeight: CGFloat
    let timeGutter: CGFloat
    let canvasHeight: CGFloat
    let isCurrent: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void
    let onPreviewMove: (Date) -> Void
    let onMove: (Date) -> Void

    @State private var isDragging: Bool = false
    @State private var dragPreviewStart: Date?
    @State private var dragOriginStart: Date?
    @State private var interactionMode: CardInteractionMode?
    @State private var horizontalOffset: CGFloat = 0
    @State private var isActionsRevealed = false

    private let trackInset: CGFloat = 8
    private let rightInset: CGFloat = 4
    /// Keep this tight so a 15-minute task looks like a 15-minute task.
    private let minHeight: CGFloat = 20
    private let cornerRadius: CGFloat = 10
    private let actionWidth: CGFloat = 112
    private let completeSwipeThreshold: CGFloat = 72
    private let revealSwipeThreshold: CGFloat = -56

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - timeGutter - trackInset - rightInset, 80)
            let height = max(minHeight, CGFloat(task.durationMinutes) / 60 * hourHeight)
            let y = yFor(task.startDate)

            ZStack(alignment: .topLeading) {
                // Action tray sits behind the card at the right edge.
                actionButtons(height: height)
                    .frame(width: actionWidth, height: height)
                    .offset(x: width - actionWidth, y: 0)
                    .allowsHitTesting(isActionsRevealed)
                    .accessibilityHidden(!isActionsRevealed)

                // "Swipe right → done" hint fills from the left edge.
                swipeCompleteHint(height: height)
                    .frame(width: min(max(horizontalOffset, 0), width), height: height, alignment: .leading)
                    .opacity(horizontalOffset > 8 ? 1 : 0)
                    .allowsHitTesting(false)

                // Card surface always receives gestures so the tray can be
                // closed by swiping right even when it is open.
                taskSurface(height: height)
                    .frame(width: width, height: height, alignment: .topLeading)
                    .offset(x: horizontalOffset)
                    .highPriorityGesture(dragGesture)
                    // Close tray on tap when it is open.
                    .onTapGesture {
                        if isActionsRevealed { closeActions(animated: true) }
                    }

                if isDragging, let dragPreviewStart {
                    dragTimePill(start: dragPreviewStart, duration: task.durationMinutes)
                        .offset(x: width - 80, y: 6)
                        .allowsHitTesting(false)
                }
            }
            .offset(x: timeGutter + trackInset, y: y)
        }
        .frame(height: canvasHeight, alignment: .topLeading)
        .allowsHitTesting(true)
    }

    // MARK: Content

    @ViewBuilder
    private func content(height: CGFloat) -> some View {
        let tight   = height < 28
        let compact = height < 50

        if tight {
            // ≤15 min strip — single line, accent bar full height.
            HStack(spacing: 0) {
                accentRail
                HStack(spacing: 5) {
                    Text(CueInTimeFormat.hourMinute(task.startDate))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(railColor.opacity(0.9))
                        .monospacedDigit()
                    Text(task.title)
                        .font(CueInTypography.micro)
                        .foregroundStyle(titleColor)
                        .strikethrough(task.isCompleted, color: CueInColors.textTertiary)
                        .lineLimit(1)
                }
                .padding(.leading, 6)
                Spacer(minLength: 4)
                completionToggle
                    .padding(.trailing, 6)
            }
        } else if compact {
            // 30–50 px — time + title side-by-side, completion toggle.
            HStack(spacing: 0) {
                accentRail
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(CueInTimeFormat.hourMinute(task.startDate))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(railColor.opacity(0.9))
                            .monospacedDigit()
                        if task.isPrimary && !task.isCompleted {
                            Circle()
                                .fill(CueInColors.accentFocus)
                                .frame(width: 4, height: 4)
                        }
                        anchorBadge
                    }
                    Text(task.title)
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(titleColor)
                        .strikethrough(task.isCompleted, color: CueInColors.textTertiary)
                        .lineLimit(1)
                }
                .padding(.leading, 8)
                .padding(.vertical, 5)
                Spacer(minLength: 4)
                completionToggle
                    .padding(.trailing, 8)
            }
        } else {
            // Full card — time range header, title, meta footer.
            HStack(alignment: .top, spacing: 0) {
                accentRail
                VStack(alignment: .leading, spacing: 3) {
                    // Time range + badges row
                    HStack(spacing: 6) {
                        Text("\(CueInTimeFormat.hourMinute(task.startDate))–\(CueInTimeFormat.hourMinute(task.endDate))")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(railColor.opacity(0.95))
                            .monospacedDigit()
                        if task.isPrimary && !task.isCompleted {
                            Circle()
                                .fill(CueInColors.accentFocus)
                                .frame(width: 5, height: 5)
                        }
                        anchorBadge
                        Spacer(minLength: 0)
                        Text(durationShort)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(CueInColors.textTertiary)
                            .monospacedDigit()
                    }
                    // Title
                    Text(task.title)
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(titleColor)
                        .strikethrough(task.isCompleted, color: CueInColors.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    // Block name / sub-label — only when there's space
                    if height > 72 {
                        Text(task.blockTitle)
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textTertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 8)
                .padding(.vertical, 8)
                Spacer(minLength: 6)
                completionToggle
                    .padding(.trailing, 10)
                    .padding(.top, 8)
            }
        }
    }

    /// A tiny pill badge for anchored card types so the origin is readable
    /// without cluttering the title row with icon glyphs.
    @ViewBuilder
    private var anchorBadge: some View {
        if task.isScheduleInjected {
            Text("SCHED")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(CueInColors.accentFocus.opacity(0.8))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    Capsule(style: .continuous)
                        .fill(CueInColors.accentFocus.opacity(0.12))
                )
        } else if task.blockType == .fixed {
            Text("FIXED")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(CueInColors.accentFixed.opacity(0.85))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    Capsule(style: .continuous)
                        .fill(CueInColors.accentFixed.opacity(0.12))
                )
        }
    }

    private func taskSurface(height: CGFloat) -> some View {
        content(height: height)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(cardBorder)
            .shadow(
                color: Color.black.opacity(isDragging ? 0.38 : 0.14),
                radius: isDragging ? 16 : 4,
                y: isDragging ? 8 : 1
            )
            .scaleEffect(isDragging ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: isDragging)
            .opacity(task.isCompleted ? 0.52 : 1.0)
    }

    private func actionButtons(height: CGFloat) -> some View {
        HStack(spacing: 0) {
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CueInColors.textPrimary)
                    .frame(width: actionWidth / 2, height: height)
                    .background(CueInColors.surfaceTertiary)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: actionWidth / 2, height: height)
                    .background(CueInColors.danger.opacity(0.86))
            }
            .buttonStyle(.plain)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func swipeCompleteHint(height: CGFloat) -> some View {
        HStack(spacing: 6) {
            Image(systemName: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
                .font(.system(size: 13, weight: .bold))
            Text(task.isCompleted ? "Undo" : "Done")
                .font(CueInTypography.micro)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.black.opacity(0.9))
        .padding(.leading, 10)
        .background(CueInColors.accentFocus)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var accentRail: some View {
        Rectangle()
            .fill(railColor)
            .frame(width: 3)
            .padding(.vertical, 6)
            .padding(.leading, 4)
    }

    private var completionToggle: some View {
        Button(action: onToggle) {
            ZStack {
                Circle()
                    .strokeBorder(
                        task.isCompleted ? CueInColors.accentFocus : CueInColors.textTertiary.opacity(0.8),
                        lineWidth: 1.5
                    )
                    .frame(width: 20, height: 20)
                if task.isCompleted {
                    Circle()
                        .fill(CueInColors.accentFocus.opacity(0.22))
                        .frame(width: 20, height: 20)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CueInColors.accentFocus)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dragTimePill(start: Date, duration: Int) -> some View {
        let end = Calendar.current.date(byAdding: .minute, value: duration, to: start) ?? start
        let label = "\(CueInTimeFormat.hourMinute(start))–\(CueInTimeFormat.hourMinute(end))"
        return Text(label)
            .font(CueInTypography.micro)
            .monospacedDigit()
            .foregroundStyle(Color.black.opacity(0.9))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(CueInColors.accentFocus.opacity(0.95)))
    }

    // MARK: Derived visuals

    private var titleColor: Color {
        task.isCompleted ? CueInColors.textTertiary : CueInColors.textPrimary
    }

    /// Left accent rail color encodes the block type at a glance.
    private var railColor: Color {
        if task.isScheduleInjected { return CueInColors.accentFocus.opacity(0.8) }
        return CueInColors.resolvedTimelineAccent(blockType: task.blockType, hex: task.timelineAccentHex)
    }

    /// Solid card background. The current task gets a visible focus tint;
    /// fixed / injected cards get a very faint type-tint so they're
    /// distinguishable without being noisy. Everything else is the base surface.
    @ViewBuilder
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(CueInColors.surfacePrimary)
            if isCurrent {
                shape.fill(CueInColors.accentFocus.opacity(0.09))
            } else if task.isScheduleInjected {
                shape.fill(CueInColors.accentFocus.opacity(0.05))
            } else if task.blockType == .fixed {
                shape.fill(CueInColors.accentFixed.opacity(0.07))
            }
        }
    }

    private var borderColor: Color {
        if isCurrent          { return CueInColors.accentFocus.opacity(0.45) }
        if task.isScheduleInjected { return CueInColors.accentFocus.opacity(0.20) }
        switch task.blockType {
        case .fixed: return CueInColors.accentFixed.opacity(0.28)
        default:     return CueInColors.cardBorder
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(borderColor, lineWidth: isCurrent ? 0.9 : 0.5)
    }

    private var metaLine: String {
        let range = "\(CueInTimeFormat.hourMinute(task.startDate))–\(CueInTimeFormat.hourMinute(task.endDate))"
        let duration = task.durationMinutes >= 60
            ? "\(task.durationMinutes / 60)h\(task.durationMinutes % 60 == 0 ? "" : " \(task.durationMinutes % 60)m")"
            : "\(task.durationMinutes)m"
        return "\(range) · \(duration) · \(task.blockTitle)"
    }

    private var durationShort: String {
        task.durationMinutes >= 60
            ? "\(task.durationMinutes / 60)h"
            : "\(task.durationMinutes)m"
    }

    // MARK: Positioning & drag

    private func yFor(_ date: Date) -> CGFloat {
        let minutes = Calendar.current.dateComponents([.minute], from: canvasStart, to: date).minute ?? 0
        return CGFloat(max(minutes, 0)) / 60 * hourHeight
    }

    /// Anchored cards cannot be dragged in the Timeline: fixed-time tasks are
    /// pinned to the clock, and schedule-injected routines are owned by the
    /// Schedule's planner — move them from the Schedule instead.
    private var isAnchor: Bool { task.isTimelineAnchor }

    private var dragGesture: some Gesture {
        // Minimum distance of 8 prevents accidental direction locks on tiny
        // finger wobbles. Direction is committed on the FIRST changed event.
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                if interactionMode == nil {
                    // Lock direction based on dominant axis of the first movement.
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    interactionMode = dx > dy ? .horizontal : .vertical
                }
                switch interactionMode {
                case .horizontal: handleHorizontalDragChanged(value)
                case .vertical:   handleVerticalDragChanged(value)
                case nil:         break
                }
            }
            .onEnded { value in
                let mode = interactionMode
                interactionMode = nil
                switch mode {
                case .horizontal:
                    handleHorizontalDragEnded(value)
                case .vertical:
                    let wasActuallyDragging = isDragging
                    isDragging = false
                    dragPreviewStart = nil
                    dragOriginStart = nil
                    if wasActuallyDragging {
                        let proposed = snappedStart(forOffset: value.translation.height)
                        UISelectionFeedbackGenerator().selectionChanged()
                        onMove(proposed)
                    }
                case nil:
                    isDragging = false
                }
            }
    }

    private func handleVerticalDragChanged(_ value: DragGesture.Value) {
        guard !isAnchor, !task.isCompleted else { return }
        if !isDragging {
            closeActions(animated: true)
            isDragging = true
            dragOriginStart = task.startDate
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        let proposed = snappedStart(forOffset: value.translation.height)
        dragPreviewStart = proposed
        onPreviewMove(proposed)
    }

    private func handleHorizontalDragChanged(_ value: DragGesture.Value) {
        guard !isDragging else { return }
        let tx = value.translation.width
        if isActionsRevealed {
            // Move relative to the fully-open position; clamp between open and closed.
            horizontalOffset = min(max(-actionWidth + tx, -actionWidth), 0)
        } else if tx > 0 {
            // Right swipe → "done" hint. Rubber-band resistance.
            horizontalOffset = min(tx * 0.85, 100)
        } else {
            // Left swipe → reveal tray.
            horizontalOffset = max(tx, -actionWidth)
        }
    }

    private func handleHorizontalDragEnded(_ value: DragGesture.Value) {
        let tx  = value.translation.width
        let vx  = value.velocity.width        // use velocity for snappier feel

        if isActionsRevealed {
            // Close if the user flicked right OR moved right beyond 20 pt.
            if tx > 20 || vx > 200 {
                resetHorizontalOffset()
            } else {
                revealActions()
            }
        } else if tx > completeSwipeThreshold {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onToggle()
            resetHorizontalOffset()
        } else if tx < revealSwipeThreshold || vx < -300 {
            UISelectionFeedbackGenerator().selectionChanged()
            revealActions()
        } else {
            resetHorizontalOffset()
        }
    }

    private func revealActions() {
        isActionsRevealed = true
        withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
            horizontalOffset = -actionWidth
        }
    }

    private func closeActions(animated: Bool) {
        isActionsRevealed = false
        if animated {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                horizontalOffset = 0
            }
        } else {
            horizontalOffset = 0
        }
    }

    private func resetHorizontalOffset() {
        isActionsRevealed = false
        withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
            horizontalOffset = 0
        }
    }

    private func snappedStart(forOffset offset: CGFloat) -> Date {
        let origin = dragOriginStart ?? task.startDate
        let minutesDelta = Int((Double(offset) / Double(hourHeight) * 60.0).rounded())
        let snap = ExecutionTimelineView.snapMinutes
        let snapped = (minutesDelta / snap) * snap
        return Calendar.current.date(byAdding: .minute, value: snapped, to: origin) ?? origin
    }

}

private enum CardInteractionMode {
    case vertical
    case horizontal
}

// MARK: - NOW pill glass modifier

/// Small capsule that displays the current clock time next to the NOW line.
/// On iOS 26 this uses the system liquid glass so it reads cleanly against
/// both dark panels and tinted cards that slide underneath it.
private struct NowPillGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(Color.white.opacity(0.08)),
                    in: .capsule
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )
        } else {
            content
                .background(
                    Capsule(style: .continuous).fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                )
        }
    }
}

