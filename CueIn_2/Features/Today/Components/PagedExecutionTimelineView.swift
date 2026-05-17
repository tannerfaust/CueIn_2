import SwiftUI

// MARK: - PagedExecutionTimelineView
/// Horizontal paged layout: one day per page, swipe left / right to move between days.
/// A glass-pill navigation strip (← date →) sits above the content as a safe-area inset,
/// mirroring the chrome-bar's visual language.

struct PagedExecutionTimelineView: View {

    // MARK: Props (same surface area as ExecutionTimelineView)

    let days: [ExecutionDayPlan]
    let currentTime: Date
    let hourHeight: CGFloat
    let onToggleTask: (Date, UUID) -> Void
    let onDeleteTask: (Date, UUID) -> Void
    let onEditTask: (Date, ExecutionTaskCard) -> Void
    let onPreviewMoveTask: (Date, UUID, Date) -> [ExecutionTaskCard]
    let onMoveTask: (Date, UUID, Date) -> Void

    // MARK: State

    @State private var selectedIndex: Int

    // MARK: Init — resolve today's index upfront so no flash on first appear

    @MainActor
    init(
        days: [ExecutionDayPlan],
        currentTime: Date,
        hourHeight: CGFloat,
        onToggleTask: @escaping (Date, UUID) -> Void,
        onDeleteTask: @escaping (Date, UUID) -> Void,
        onEditTask: @escaping (Date, ExecutionTaskCard) -> Void,
        onPreviewMoveTask: @escaping (Date, UUID, Date) -> [ExecutionTaskCard],
        onMoveTask: @escaping (Date, UUID, Date) -> Void
    ) {
        self.days = days
        self.currentTime = currentTime
        self.hourHeight = hourHeight
        self.onToggleTask = onToggleTask
        self.onDeleteTask = onDeleteTask
        self.onEditTask = onEditTask
        self.onPreviewMoveTask = onPreviewMoveTask
        self.onMoveTask = onMoveTask

        let todayIndex = days.firstIndex(where: {
            Calendar.current.isDate($0.date, inSameDayAs: currentTime)
        }) ?? 0
        self._selectedIndex = State(initialValue: todayIndex)
    }

    // MARK: Body

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                ExecutionTimelineView(
                    days: [day],
                    currentTime: currentTime,
                    hourHeight: hourHeight,
                    showDayHeaders: false,
                    onToggleTask: onToggleTask,
                    onDeleteTask: onDeleteTask,
                    onEditTask: onEditTask,
                    onPreviewMoveTask: onPreviewMoveTask,
                    onMoveTask: onMoveTask
                )
                .tag(index)
            }
        }
        .cueInPageTabViewStyle()
        .onChange(of: daysPageIdentity) { _, _ in
            clampSelectedIndexToValidDayRange()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            dateNavStrip
        }
    }

    /// Single snapshot for count + day identity (avoids two `onChange` passes and a raw `[Date]` array).
    private var daysPageIdentity: String {
        if days.isEmpty { return "0" }
        return "\(days.count)|" + days.map { String($0.id.timeIntervalSince1970) }.joined(separator: ",")
    }

    private func clampSelectedIndexToValidDayRange() {
        guard !days.isEmpty else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(0, selectedIndex), days.count - 1)
    }

    // MARK: Navigation strip

    private var canGoBack:    Bool { selectedIndex > 0 }
    private var canGoForward: Bool { selectedIndex < days.count - 1 }

    private var currentDay: ExecutionDayPlan? {
        guard selectedIndex < days.count else { return nil }
        return days[selectedIndex]
    }

    private var dateNavStrip: some View {
        HStack(spacing: CueInSpacing.sm) {
            // ← previous day
            navButton(systemImage: "chevron.left", enabled: canGoBack) {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                    selectedIndex -= 1
                }
            }

            Spacer(minLength: 0)

            // Date pill — centre
            if let day = currentDay {
                DayNavPill(date: day.date, currentTime: currentTime)
            }

            Spacer(minLength: 0)

            // → next day
            navButton(systemImage: "chevron.right", enabled: canGoForward) {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                    selectedIndex += 1
                }
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.top, CueInLayout.executionDateNavTopPadding)
        .padding(.bottom, CueInLayout.executionDateNavBottomPadding)
        .frame(minHeight: CueInLayout.executionDateNavHeight)
    }

    @ViewBuilder
    private func navButton(
        systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    enabled
                        ? CueInColors.textPrimary
                        : CueInColors.textTertiary.opacity(0.35)
                )
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - DayNavPill
/// Glass capsule showing the day label: "Today · Fri 24 Apr", "Tomorrow · …", or just the date.

private struct DayNavPill: View {
    let date: Date
    let currentTime: Date

    private var cal: Calendar { .current }

    private var isToday: Bool {
        cal.isDate(date, inSameDayAs: currentTime)
    }

    private var relativeName: String? {
        if isToday { return "Today" }
        if let tomorrow = cal.date(byAdding: .day, value:  1, to: cal.startOfDay(for: currentTime)),
           cal.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: currentTime)),
           cal.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        return nil
    }

    private var datePart: String {
        let refYear = cal.component(.year, from: currentTime)
        let dayYear = cal.component(.year, from: date)
        if dayYear != refYear {
            return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    var body: some View {
        Group {
            if let rel = relativeName {
                HStack(spacing: 0) {
                    Text(rel)
                        .foregroundStyle(isToday ? CueInColors.accentFocus : CueInColors.textPrimary)
                    Text("  ·  \(datePart)")
                        .foregroundStyle(CueInColors.textTertiary)
                }
            } else {
                Text(datePart)
                    .foregroundStyle(CueInColors.textSecondary)
            }
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .modifier(TodayCapsuleGlassModifier())
    }
}
