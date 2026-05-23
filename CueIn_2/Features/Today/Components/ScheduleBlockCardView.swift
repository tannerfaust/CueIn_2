import SwiftUI

/// When set by the timeline, swipe/reorder gestures are attached to the **main+spacer** band only,
/// so state controls on the **leading** and **trailing** columns stay tappable.
struct ScheduleBlockMainRowGestureActions {
    let allowsLongPress: Bool
    let onBegan: (CGPoint) -> Void
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void
    let onCancelled: () -> Void
    let onTapped: () -> Void
}

private struct ScheduleBlockMainRowGestureKey: EnvironmentKey {
    static let defaultValue: ScheduleBlockMainRowGestureActions? = nil
}

extension EnvironmentValues {
    var scheduleBlockMainRowGesture: ScheduleBlockMainRowGestureActions? {
        get { self[ScheduleBlockMainRowGestureKey.self] }
        set { self[ScheduleBlockMainRowGestureKey.self] = newValue }
    }
}

// MARK: - ScheduleBlockCardView
/// Frame-first card used only by Schedule mode.

struct ScheduleBlockCardView: View {
    @AppStorage(TodayDisplayPreferences.activeBlockEmphasis) private var activeBlockEmphasisRaw
        = TodayDisplayPreferences.ActiveBlockEmphasis.brand.rawValue
    @State private var showFinishChevronPopover = false
    @State private var showRemindersEllipsisPopover = false

    @Environment(\.scheduleBlockMainRowGesture) private var scheduleBlockMainRowGesture

    let block: DayBlock
    let isCurrentBlock: Bool
    var design: TodayDisplayPreferences.ScheduleDesign = .glass
    /// When the Today canvas is on, **Liquid glass** design uses iOS 26 `glassEffect` (real liquid glass) instead of flat tint + `ultraThinMaterial`.
    var useCanvasLiquidGlass: Bool = false
    /// Holds live timer UI at this instant when the formula run is paused.
    var frozenLiveProgressDate: Date? = nil
    let showsStartTime: Bool
    let showsDuration: Bool
    let showsTimeRange: Bool
    let showsFinishControl: Bool
    let showsCompletedToggle: Bool
    let isLiveRun: Bool
    let timerStyle: TodayDisplayPreferences.ScheduleBlockTimerStyle
    let showsTimerSeconds: Bool
    let onCompleteBlock: () -> Void
    let onFinishBlockKeepingPending: () -> Void
    let onRevertCompletedBlock: () -> Void
    let onToggleTask: (UUID) -> Void
    var onAddTask: (() -> Void)? = nil
    var onOpenFocus: (() -> Void)? = nil

    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var dragOffset: CGFloat = 0
    @State private var isSwipeOpen = false

    private var swipeActionWidth: CGFloat { 140 }
    private var swipeMaxReveal: CGFloat { 164 }
    private var swipeSettleAnimation: Animation {
        .interactiveSpring(response: 0.24, dampingFraction: 0.88, blendDuration: 0.02)
    }

    private var blockEmphasis: TodayDisplayPreferences.ActiveBlockEmphasis {
        TodayDisplayPreferences.migratedActiveBlockEmphasis(from: activeBlockEmphasisRaw)
    }

    /// Block accent from Look (custom swatch or lane default) — drives the running card wash and chrome.
    private var blockTimelineAccent: Color {
        CueInColors.resolvedTimelineAccent(blockType: block.type, hex: block.timelineAccentHex)
    }

    /// Running block timer, ring, border, and wash use the block accent; global emphasis is not used here.
    private var runningAccent: Color {
        isCurrentBlock ? blockTimelineAccent : blockEmphasis.primary
    }

    private var isRoutineBlock: Bool {
        block.isRepeatable && block.taskSource == .templateTasks
    }

    /// Shown on the card so fixed / timeline-anchor blocks are visually distinct from flexible flow blocks.
    private var showsClockPinnedIndicator: Bool {
        block.pinsToClock || block.isAnchorBlock
    }

    private var showsActiveTasks: Bool {
        isLiveRun && isCurrentBlock && !block.tasks.isEmpty
    }

    private var showsRunningBlockAddTask: Bool {
        isLiveRun && isCurrentBlock && block.state == .active && onAddTask != nil
    }

    private var isCompletedBlock: Bool {
        block.state == .completed
    }

    private var remindersListBodySpacing: CGFloat {
        design == .reminders ? 6 : CueInSpacing.sm
    }

    /// How this block relates to tasks: icon-only cue at the bottom of the card (not long prose in the header).
    private enum TaskLinkageVisual {
        case none
        case autoFromTodo
        case manualInBlock
    }

    private var taskLinkageVisual: TaskLinkageVisual {
        switch block.taskSource {
        case .noTasks:
            return .none
        case .executionFill:
            return .autoFromTodo
        case .templateTasks:
            return .manualInBlock
        }
    }

    private var taskLinkageIconName: String {
        switch taskLinkageVisual {
        case .none: return "tray"
        case .autoFromTodo: return "sparkles"
        case .manualInBlock: return "checklist"
        }
    }

    private var taskLinkageAccessibilityLabel: String {
        switch taskLinkageVisual {
        case .none: return "No tasks in this block"
        case .autoFromTodo: return "Tasks link automatically from To-do"
        case .manualInBlock: return "Tasks assigned in this block"
        }
    }

    /// Fill-mode cue (checklist / sparkles). Hidden on the live, active block where tasks are shown inline.
    private var showsTaskLinkageIndicator: Bool {
        if isCompletedBlock { return false }
        if showsActiveTasks { return false }
        if isLiveRun, block.state == .active { return false }
        return true
    }

    @ViewBuilder
    private var taskLinkageIconRow: some View {
        if showsTaskLinkageIndicator {
            taskLinkageIconRowContent
        }
    }

    private var taskLinkageIconRowContent: some View {
        HStack(spacing: 0) {
            Image(systemName: taskLinkageIconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CueInColors.textTertiary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(CueInColors.surfaceTertiary.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(CueInColors.cardBorder.opacity(0.35), lineWidth: 0.5)
                )
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(taskLinkageAccessibilityLabel)
    }

    /// Title + body + tasks (no state rail); paired with `trailingColumn` when a timeline gesture is injected.
    private var mainColumn: some View {
        HStack(alignment: .top, spacing: 8) {
            longPressableMainContent
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var trailingColumn: some View {
        trailingControl
            .padding(.top, 2)
    }

    /// HStack{ main, Spacer, trailing } in Today, or a ZStack that keeps the state rail *above* the main-row hit-test.
    /// Gesture layer uses `.background` to avoid `_UIReparentingView` warnings from UIKit/SwiftUI bridge.
    @ViewBuilder
    private var mainAndTrailing: some View {
        if let attach = scheduleBlockMainRowGesture {
            ZStack(alignment: .trailing) {
                mainColumn
                    .background {
                        GeometryReader { proxy in
                            let leadingHitInset: CGFloat = design == .glass ? 72 : 0
                            BlockMainInteractionGestureView(
                                actions: attach,
                                onSwipeChanged: handleSwipeChanged(translationX:),
                                onSwipeEnded: handleSwipeEnded(translationX:velocityX:)
                            )
                                .frame(
                                    width: max(proxy.size.width - leadingHitInset, 0),
                                    height: proxy.size.height
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        }
                    }
                trailingColumn
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                longPressableMainContent
                Spacer(minLength: 0)
                trailingColumn
            }
        }
    }

    var body: some View {
        let chrome = Group {
            switch design {
            case .glass:
                mainAndTrailing
                    .padding(glassCardPadding)
                    .modifier(
                        ScheduleBlockGlassDesignModifier(
                            useCanvasLiquidGlass: useCanvasLiquidGlass,
                            isCurrentBlock: isCurrentBlock,
                            isCompleted: isCompletedBlock,
                            cornerRadius: isCompletedBlock ? 18 : 22,
                            runningPrimary: blockTimelineAccent
                        )
                    )
            case .reminders:
                HStack(alignment: .top, spacing: isCompletedBlock ? 8 : 10) {
                    remindersCompletionDisk
                    mainAndTrailing
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, isCompletedBlock ? 3 : 6)
                .background {
                    if isCurrentBlock, !isCompletedBlock {
                        RoundedRectangle(cornerRadius: 0, style: .continuous)
                            .fill(CueInColors.scheduleRunningBlockWash(accent: blockTimelineAccent))
                    }
                }
            case .agenda:
                HStack(alignment: .top, spacing: isCompletedBlock ? 8 : 10) {
                    agendaTimeGutter
                    RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                        .fill(CueInColors.divider.opacity(isCompletedBlock ? 0.45 : 1))
                        .frame(width: 1, height: isCompletedBlock ? 32 : 40)
                    mainAndTrailing
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, isCompletedBlock ? 2 : 0)
            }
        }

        return ZStack(alignment: .trailing) {
            if dragOffset < 0 {
                swipeBackground
            }
            chrome
                .modifier(ScheduleBlockCompletedAppearanceModifier(isCompleted: isCompletedBlock))
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: design.blockInteractionClipRadius,
                        style: .continuous
                    )
                )
                .offset(x: dragOffset)
                .background {
                    if scheduleBlockMainRowGesture == nil {
                        HorizontalSwipeGestureView(
                            onChanged: handleSwipeChanged(translationX:),
                            onEnded: handleSwipeEnded(translationX:velocityX:)
                        )
                    }
                }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: isCompletedBlock)
    }

    private var glassCardPadding: EdgeInsets {
        if isCompletedBlock {
            return EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        }
        return EdgeInsets(
            top: CueInSpacing.base,
            leading: CueInSpacing.base,
            bottom: CueInSpacing.base,
            trailing: CueInSpacing.base
        )
    }

    private var agendaTimeGutter: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(agendaStartString)
                .font(isCompletedBlock ? CueInTypography.micro : CueInTypography.caption)
                .monospacedDigit()
                .foregroundStyle(
                    isCompletedBlock
                        ? CueInColors.textTertiary
                        : (isCurrentBlock ? runningAccent : CueInColors.textSecondary)
                )
            if showsTimeRange {
                Text(agendaEndString)
                    .font(CueInTypography.micro)
                    .monospacedDigit()
                    .foregroundStyle(CueInColors.textTertiary)
            }
        }
        .frame(width: 50, alignment: .trailing)
    }

    // MARK: - Swipe Background & Gesture

    @ViewBuilder
    private var swipeBackground: some View {
        HStack(spacing: 0) {
            Spacer()
            
            Button {
                withAnimation(swipeSettleAnimation) {
                    dragOffset = 0
                    isSwipeOpen = false
                }
                onEdit?()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Edit")
                        .font(CueInTypography.micro)
                        .fontWeight(.medium)
                }
                .frame(width: 70)
                .frame(maxHeight: .infinity)
                .background(Color.blue)
                .foregroundColor(.white)
            }
            
            Button {
                withAnimation(swipeSettleAnimation) {
                    dragOffset = 0
                    isSwipeOpen = false
                }
                onDelete?()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Delete")
                        .font(CueInTypography.micro)
                        .fontWeight(.medium)
                }
                .frame(width: 70)
                .frame(maxHeight: .infinity)
                .background(CueInColors.danger)
                .foregroundColor(.white)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: design.blockInteractionClipRadius, style: .continuous))
    }

    private func rubberBandedSwipeOffset(_ proposed: CGFloat) -> CGFloat {
        if proposed >= 0 {
            return 0
        }
        if proposed < -swipeMaxReveal {
            return -swipeMaxReveal + ((proposed + swipeMaxReveal) * 0.22)
        }
        return proposed
    }

    private func handleSwipeChanged(translationX: CGFloat) {
        let startX: CGFloat = isSwipeOpen ? -swipeActionWidth : 0
        dragOffset = rubberBandedSwipeOffset(startX + translationX)
    }

    private func handleSwipeEnded(translationX: CGFloat, velocityX: CGFloat) {
        let startX: CGFloat = isSwipeOpen ? -swipeActionWidth : 0
        let newX = startX + translationX
        let projectedX = newX + (velocityX * 0.18)
        let shouldOpen = min(newX, projectedX) < -(swipeActionWidth * 0.48)

        withAnimation(swipeSettleAnimation) {
            dragOffset = shouldOpen ? -swipeActionWidth : 0
            isSwipeOpen = shouldOpen
        }
    }

    private var agendaStartString: String { startTimeLabel }
    private var agendaEndString: String {
        CueInTimeFormat.hourMinute(block.endTime)
    }

    /// Reminders-style ring: tap to finish the block (or tap check to undo) — the only “Finish” control for this design.
    @ViewBuilder
    private var remindersCompletionDisk: some View {
        let ring: CGFloat = 24

        switch block.state {
        case .active:
            if showsFinishControl {
                Button {
                    CueInHaptics.impact(.light)
                    onFinishBlockKeepingPending()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(
                                (isCurrentBlock ? runningAccent : CueInColors.textTertiary)
                                    .opacity(isCurrentBlock ? 0.95 : 0.4),
                                lineWidth: isCurrentBlock ? 2.1 : 1.1
                            )
                            .frame(width: ring, height: ring)
                    }
                    .frame(minWidth: 32, minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Finish block")
            } else {
                Circle()
                    .stroke(CueInColors.textTertiary.opacity(0.3), lineWidth: 1)
                    .frame(width: ring, height: ring)
            }
        case .completed:
            if showsCompletedToggle {
                Button {
                    CueInHaptics.impact(.light)
                    onRevertCompletedBlock()
                } label: {
                    ZStack {
                        Circle()
                            .fill(CueInColors.textTertiary.opacity(0.22))
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CueInColors.textSecondary)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark block as not done")
            } else {
                ZStack {
                    Circle()
                        .stroke(CueInColors.textTertiary.opacity(0.3), lineWidth: 1)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CueInColors.textTertiary)
                }
                .frame(width: ring, height: ring)
            }
        case .upcoming:
            Circle()
                .stroke(CueInColors.textTertiary.opacity(0.35), lineWidth: 1)
                .frame(width: ring, height: ring)
        case .skipped:
            ZStack {
                Circle()
                    .stroke(CueInColors.textTertiary.opacity(0.25), lineWidth: 1)
                    .frame(width: ring, height: ring)
                Image(systemName: "forward")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CueInColors.textTertiary.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private var longPressableMainContent: some View {
        VStack(alignment: .leading, spacing: remindersListBodySpacing) {
            blockHeader
            if isCurrentBlock, design != .glass {
                liveRunIndicator
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .move(edge: .top))
                            .combined(with: .scale(scale: 0.96, anchor: .top)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        )
                    )
            }
            if showsActiveTasks {
                compactTaskList
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .move(edge: .top))
                            .combined(with: .scale(scale: 0.98, anchor: .top)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        )
                    )
            }
            if showsRunningBlockAddTask, let onAddTask {
                if !showsActiveTasks {
                    Rectangle()
                        .fill(CueInColors.divider.opacity(design == .reminders ? 0.35 : 0.7))
                        .frame(height: 0.5)
                        .padding(.vertical, design == .reminders ? CueInSpacing.xs * 0.5 : CueInSpacing.xs)
                }
                runningBlockAddTaskButton(action: onAddTask)
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .move(edge: .top))
                            .combined(with: .scale(scale: 0.98, anchor: .top)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        )
                    )
            }
            taskLinkageIconRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.04), value: isCurrentBlock)
        .animation(.spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.04), value: showsActiveTasks)
        .animation(.spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.04), value: showsRunningBlockAddTask)
    }

    @ViewBuilder
    private var blockHeader: some View {
        switch design {
        case .glass:
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .top, spacing: CueInSpacing.sm) {
                    if showsGlassLeadingCompletionSlot {
                        glassBlockCompletionLeading
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    blockIdentityGlyph
                    titleAndMetaVStack
                        .padding(.trailing, glassTrailingInset)
                    Spacer(minLength: 0)
                }
                if isCurrentBlock {
                    glassCornerRunControls
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .topTrailing)))
                } else if showsGlassPlannedDurationBadge {
                    glassCornerPlannedDurationBadge
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .topTrailing)))
                }
            }
        case .reminders, .agenda:
            titleAndMetaVStack
        }
    }

    /// Keep upcoming blocks visually tighter to the leading edge; once started,
    /// add a leading slot for the completion control.
    private var showsGlassLeadingCompletionSlot: Bool {
        block.state != .upcoming
    }

    private var titleAndMetaVStack: some View {
        VStack(alignment: .leading, spacing: isCompletedBlock ? 3 : 6) {
            HStack(alignment: .center, spacing: CueInSpacing.sm) {
                Text(block.title)
                    .font(completedTitleFont)
                    .foregroundStyle(isCompletedBlock ? CueInColors.textTertiary : CueInColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if isRoutineBlock {
                    routineTag
                        .opacity(isCompletedBlock ? 0.65 : 1)
                }
                if showsClockPinnedIndicator {
                    clockPinnedTag
                        .opacity(isCompletedBlock ? 0.65 : 1)
                }
            }

            if showsMetaLine {
                metaLine
            }
        }
    }

    private var completedTitleFont: Font {
        switch design {
        case .glass:
            return CueInTypography.bodyMedium
        case .reminders, .agenda:
            return CueInTypography.captionMedium
        }
    }

    private var blockIdentityGlyph: some View {
        let glyphSize: CGFloat = isCompletedBlock ? 24 : 30
        let iconPointSize: CGFloat = isCompletedBlock ? 11 : 13
        let corner: CGFloat = isCompletedBlock ? 8 : 10
        return Image(systemName: block.resolvedTimelineGlyph)
            .font(.system(size: iconPointSize, weight: .semibold))
            .foregroundStyle(
                isCompletedBlock
                    ? CueInColors.textTertiary.opacity(0.85)
                    : (isCurrentBlock
                        ? runningAccent
                        : CueInColors.resolvedTimelineAccent(blockType: block.type, hex: block.timelineAccentHex))
            )
            .frame(width: glyphSize, height: glyphSize)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        CueInColors.surfaceTertiary.opacity(
                            isCompletedBlock ? 0.38 : (isRoutineBlock ? 0.72 : 0.52)
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(isCompletedBlock ? 0.04 : 0.06),
                        lineWidth: 0.5
                    )
            }
    }

    // MARK: - Glass — leading completion + top-trailing timer

    @ViewBuilder
    private var glassBlockCompletionLeading: some View {
        let roundedBox: CGFloat = 26
        Group {
            switch block.state {
            case .active:
                if showsFinishControl {
                    Button {
                        CueInHaptics.impact(.light)
                        onFinishBlockKeepingPending()
                    } label: {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(
                                (isCurrentBlock ? runningAccent : CueInColors.textTertiary)
                                    .opacity(isCurrentBlock ? 0.95 : 0.45),
                                lineWidth: isCurrentBlock ? 2 : 1.5
                            )
                            .frame(width: roundedBox, height: roundedBox)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Finish block")
                } else {
                    Color.clear.frame(width: 30, height: 30)
                }
            case .completed:
                if showsCompletedToggle {
                    Button {
                        CueInHaptics.impact(.light)
                        onRevertCompletedBlock()
                    } label: {
                        glassCompletedCheckDisk
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mark block as not done")
                } else {
                    glassCompletedCheckDisk
                }
            case .skipped:
                Image(systemName: "forward")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CueInColors.textTertiary.opacity(0.55))
                    .frame(width: 30, height: 30)
            case .upcoming:
                Color.clear.frame(width: 30, height: 30)
            }
        }
        .frame(width: 30, alignment: .center)
        .padding(.top, 2)
    }

    private var glassCompletedCheckDisk: some View {
        let disk: CGFloat = isCompletedBlock ? 24 : 28
        return ZStack {
            Circle()
                .fill(isCompletedBlock ? CueInColors.textTertiary.opacity(0.22) : Color.white)
            Image(systemName: "checkmark")
                .font(.system(size: isCompletedBlock ? 10 : 11, weight: .bold))
                .foregroundStyle(
                    isCompletedBlock ? CueInColors.textSecondary : Color.black.opacity(0.78)
                )
        }
        .frame(width: disk, height: disk)
    }

    private var glassCornerLiveTimer: some View {
        withLiveTimerClock { now in
            let progress = liveTimerProgress(at: now)
            let accent = liveTimerAccent(at: now)
            let isOvertime = isLiveTimerOvertime(at: now)
            let ring: CGFloat = 34

            ZStack {
                switch timerStyle {
                case .ring:
                    Circle()
                        .stroke(CueInColors.surfaceTertiary.opacity(0.55), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            accent.opacity(0.92),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    liveTimerRingText(
                        liveTimerRingLabel(at: now),
                        isOvertime: isOvertime,
                        accent: accent,
                        primaryStyle: false
                    )
                case .pulse:
                    Circle()
                        .fill(accent.opacity(0.14 + (0.18 * progress)))
                    Circle()
                        .stroke(accent.opacity(0.8), lineWidth: 1.5)
                    liveTimerRingText(
                        liveTimerRingLabel(at: now),
                        isOvertime: isOvertime,
                        accent: accent,
                        primaryStyle: true
                    )
                case .bars:
                    VStack(spacing: 4) {
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { idx in
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(progress >= (Double(idx + 1) / 5.0) ? accent.opacity(0.9) : CueInColors.surfaceTertiary.opacity(0.65))
                                    .frame(width: 5, height: 6)
                            }
                        }
                        liveTimerRingText(
                            liveTimerRingLabel(at: now),
                            isOvertime: isOvertime,
                            accent: accent,
                            primaryStyle: false
                        )
                    }
                case .minimal:
                    liveTimerRingText(
                        liveTimerRingLabel(at: now),
                        isOvertime: isOvertime,
                        accent: accent,
                        primaryStyle: false,
                        fontSize: 10
                    )
                }
            }
            .frame(width: ring, height: ring)
            .animation(nil, value: progress)
        }
        .accessibilityLabel(liveTimerAccessibilityLabel(at: frozenLiveProgressDate ?? Date()))
    }

    private var routineTag: some View {
        Text("Routine")
            .font(CueInTypography.micro)
            .foregroundStyle(CueInColors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(CueInColors.surfaceTertiary.opacity(0.88))
            )
    }

    private var clockPinnedTag: some View {
        HStack(spacing: 4) {
            Image(systemName: "pin.fill")
                .font(.system(size: 9, weight: .semibold))
            Text("Pinned")
                .font(CueInTypography.micro)
            Text(startTimeLabel)
                .font(CueInTypography.micro)
                .monospacedDigit()
        }
        .foregroundStyle(CueInColors.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(CueInColors.surfaceTertiary.opacity(0.88))
        )
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Pinned at \(startTimeLabel)")
    }

    private var glassTrailingInset: CGFloat {
        if isCurrentBlock {
            let focusSlot: CGFloat = onOpenFocus != nil ? 38 : 0
            return 40 + focusSlot
        }
        if showsGlassPlannedDurationBadge { return 58 }
        return 0
    }

    @ViewBuilder
    private var glassCornerRunControls: some View {
        HStack(spacing: 6) {
            if let onOpenFocus {
                Button(action: onOpenFocus) {
                    Image(systemName: "scope")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(blockTimelineAccent)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(blockTimelineAccent.opacity(0.16))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(blockTimelineAccent.opacity(0.38), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Focus mode")
            }
            glassCornerLiveTimer
        }
    }

    private var showsGlassPlannedDurationBadge: Bool {
        design == .glass && block.state == .upcoming && showsDuration
    }

    private var glassCornerPlannedDurationBadge: some View {
        Text("\(block.durationMinutes)m")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(CueInColors.textSecondary)
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(CueInColors.surfaceTertiary.opacity(0.72))
            )
            .accessibilityLabel("Planned duration \(block.durationMinutes) minutes")
    }

    private var showsMetaLine: Bool {
        !metaItems.isEmpty
    }

    private var metaLine: some View {
        HStack(spacing: 6) {
            ForEach(Array(metaItems.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Text("·")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary.opacity(0.6))
                }

                Text(item)
                    .font(isCompletedBlock ? CueInTypography.micro : CueInTypography.caption)
                    .foregroundStyle(
                        isCompletedBlock
                            ? CueInColors.textTertiary.opacity(0.75)
                            : CueInColors.textSecondary
                    )
                    .monospacedDigit()
            }
        }
    }

    private var metaItems: [String] {
        var items: [String] = []
        if showsDuration && !isLiveRun && !showsGlassPlannedDurationBadge {
            items.append("\(block.durationMinutes)m")
        }
        if showsTimeRange {
            items.append(block.timeRangeLabel)
        } else if showsStartTime {
            items.append(startTimeLabel)
        }
        return items
    }

    private var startTimeLabel: String {
        CueInTimeFormat.hourMinute(block.startTime)
    }

    private var overtimeTimerColor: Color { CueInColors.danger }

    private func liveTimerRemainingSeconds(at date: Date) -> Int {
        Int(block.endTime.timeIntervalSince(date))
    }

    private func isLiveTimerOvertime(at date: Date) -> Bool {
        isCurrentBlock && liveTimerRemainingSeconds(at: date) <= 0
    }

    private func liveTimerAccent(at date: Date) -> Color {
        isLiveTimerOvertime(at: date) ? overtimeTimerColor : runningAccent
    }

    private func liveTimerProgress(at date: Date) -> Double {
        let total = max(block.endTime.timeIntervalSince(block.startTime), 1)
        let elapsed = date.timeIntervalSince(block.startTime)
        return min(max(elapsed / total, 0), 1)
    }

    /// Compact label for the 34pt corner ring so overtime never wraps (e.g. `-3:41` not `-03:41`).
    private func liveTimerRingLabel(at date: Date) -> String {
        let remaining = liveTimerRemainingSeconds(at: date)
        if remaining > 0 {
            if showsTimerSeconds || frozenLiveProgressDate != nil {
                return compactDigitalDurationLabel(totalSeconds: remaining)
            }
            let minutes = max(Int(ceil(Double(remaining) / 60.0)), 1)
            return "\(minutes)m"
        }
        let overtimeSeconds = -remaining
        if showsTimerSeconds || frozenLiveProgressDate != nil {
            return "-\(compactDigitalDurationLabel(totalSeconds: overtimeSeconds))"
        }
        let minutes = max(Int(ceil(Double(overtimeSeconds) / 60.0)), 1)
        return "-\(minutes)m"
    }

    private func liveTimerLabel(at date: Date) -> String {
        let remaining = liveTimerRemainingSeconds(at: date)
        if remaining > 0 {
            if showsTimerSeconds || frozenLiveProgressDate != nil {
                return digitalDurationLabel(totalSeconds: remaining)
            }
            let minutes = max(Int(ceil(Double(remaining) / 60.0)), 1)
            return "\(minutes)m"
        }
        let overtimeSeconds = -remaining
        if showsTimerSeconds || frozenLiveProgressDate != nil {
            return "-\(digitalDurationLabel(totalSeconds: overtimeSeconds))"
        }
        let minutes = max(Int(ceil(Double(overtimeSeconds) / 60.0)), 1)
        return "-\(minutes)m"
    }

    /// `m:ss` without a leading zero on minutes — fits small timer rings.
    private func compactDigitalDurationLabel(totalSeconds: Int) -> String {
        let safe = max(totalSeconds, 0)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let seconds = safe % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func digitalDurationLabel(totalSeconds: Int) -> String {
        let safe = max(totalSeconds, 0)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let seconds = safe % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func liveTimerRingText(
        _ label: String,
        isOvertime: Bool,
        accent: Color,
        primaryStyle: Bool,
        fontSize: CGFloat = 9
    ) -> some View {
        Text(label)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(
                isOvertime
                    ? accent
                    : (primaryStyle ? CueInColors.textPrimary : CueInColors.textSecondary)
            )
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .allowsTightening(true)
            .frame(width: 26)
    }

    private func liveTimerAccessibilityLabel(at date: Date) -> String {
        let remaining = liveTimerRemainingSeconds(at: date)
        if remaining > 0 {
            if showsTimerSeconds || frozenLiveProgressDate != nil {
                return "\(digitalDurationLabel(totalSeconds: remaining)) remaining"
            }
            let minutes = max(Int(ceil(Double(remaining) / 60.0)), 1)
            return "\(minutes) minutes remaining"
        }
        let overtimeSeconds = -remaining
        if showsTimerSeconds || frozenLiveProgressDate != nil {
            return "\(digitalDurationLabel(totalSeconds: overtimeSeconds)) overtime"
        }
        let minutes = max(Int(ceil(Double(overtimeSeconds) / 60.0)), 1)
        return "\(minutes) minutes overtime"
    }

    @ViewBuilder
    private var trailingControl: some View {
        stateIndicator
    }

    @ViewBuilder
    private var stateIndicator: some View {
        if design == .reminders {
            remindersListTrailing
        } else if design == .glass {
            EmptyView()
        } else {
            standardStateIndicator
        }
    }

    /// Ellipsis menu only for “complete all”; primary finish is the leading ring.
    @ViewBuilder
    private var remindersListTrailing: some View {
        if block.state == .active && showsFinishControl {
            Button {
                showRemindersEllipsisPopover = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CueInColors.textTertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More block actions")
            .popover(isPresented: $showRemindersEllipsisPopover) {
                List {
                    Button {
                        onCompleteBlock()
                        showRemindersEllipsisPopover = false
                    } label: {
                        Label("Complete all tasks in this block", systemImage: "checkmark.seal")
                    }
                }
                .frame(minWidth: 280)
                .fixedSize(horizontal: false, vertical: true)
                .presentationCompactAdaptation(.popover)
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var standardStateIndicator: some View {
        switch block.state {
        case .active:
            if showsFinishControl {
                // Split primary tap vs overflow menu. `Menu`+`primaryAction` routes through
                // UIMenu / context-menu infrastructure and is a common source of
                // "updateVisibleMenuWithBlock while no context menu" + reparenting noise on iOS 18+.
                HStack(spacing: 0) {
                    Button {
                        CueInHaptics.impact(.light)
                        onFinishBlockKeepingPending()
                    } label: {
                        Text("Finish")
                            .font(CueInTypography.captionMedium)
                            .foregroundStyle(CueInColors.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showFinishChevronPopover = true
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(CueInColors.textPrimary)
                            .frame(width: 24, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showFinishChevronPopover) {
                        List {
                            Button {
                                CueInHaptics.impact(.light)
                                onFinishBlockKeepingPending()
                                showFinishChevronPopover = false
                            } label: {
                                Label("Finish block", systemImage: "flag.checkered")
                            }
                            Button {
                                CueInHaptics.impact(.light)
                                onCompleteBlock()
                                showFinishChevronPopover = false
                            } label: {
                                Label("Finish & complete all tasks", systemImage: "checkmark.seal")
                            }
                        }
                        .frame(minWidth: 240)
                        .fixedSize(horizontal: false, vertical: true)
                        .presentationCompactAdaptation(.popover)
                    }
                }
                .background(CueInColors.surfaceTertiary, in: Capsule(style: .continuous))
            }
        case .completed:
            if showsCompletedToggle {
                Button(action: onRevertCompletedBlock) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(CueInColors.textSecondary)
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
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
        withLiveTimerClock { now in
            let progress = liveTimerProgress(at: now)
            let accent = liveTimerAccent(at: now)
            let isOvertime = isLiveTimerOvertime(at: now)

            HStack(spacing: CueInSpacing.md) {
                ZStack {
                    switch timerStyle {
                    case .ring:
                        Circle()
                            .stroke(CueInColors.surfaceTertiary.opacity(0.95), lineWidth: 4)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                accent.opacity(0.9),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))

                        Text(liveTimerLabel(at: now))
                            .font(CueInTypography.micro)
                            .foregroundStyle(isOvertime ? accent : CueInColors.textSecondary)
                            .monospacedDigit()
                    case .pulse:
                        Circle()
                            .fill(accent.opacity(0.12 + (0.2 * progress)))
                        Circle()
                            .stroke(accent.opacity(0.85), lineWidth: 2)
                        Text(liveTimerLabel(at: now))
                            .font(CueInTypography.micro)
                            .foregroundStyle(isOvertime ? accent : CueInColors.textPrimary)
                            .monospacedDigit()
                    case .bars:
                        VStack(spacing: 5) {
                            HStack(spacing: 3) {
                                ForEach(0..<8, id: \.self) { idx in
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(progress >= (Double(idx + 1) / 8.0) ? accent.opacity(0.9) : CueInColors.surfaceTertiary.opacity(0.7))
                                        .frame(width: 3, height: 8)
                                }
                            }
                            Text(liveTimerLabel(at: now))
                                .font(CueInTypography.micro)
                                .foregroundStyle(isOvertime ? accent : CueInColors.textSecondary)
                                .monospacedDigit()
                        }
                    case .minimal:
                        Text(liveTimerLabel(at: now))
                            .font(CueInTypography.captionMedium)
                            .foregroundStyle(accent.opacity(0.95))
                            .monospacedDigit()
                    }
                }
                .frame(width: 38, height: 38)
                .animation(nil, value: progress)

                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .accessibilityLabel(liveTimerAccessibilityLabel(at: frozenLiveProgressDate ?? Date()))
    }

    /// Keep the progress indicator cadence tied to the user's timer precision setting.
    private var timerTickInterval: TimeInterval {
        showsTimerSeconds ? 1 : 30
    }

    /// Single `TimelineView` so pause/resume does not swap view roots (which re-triggered ring `.trim` animations from zero).
    @ViewBuilder
    private func withLiveTimerClock<Content: View>(
        @ViewBuilder content: @escaping (Date) -> Content
    ) -> some View {
        TimelineView(.periodic(from: .now, by: timerTickInterval)) { context in
            let referenceNow = frozenLiveProgressDate ?? context.date
            content(referenceNow)
        }
    }

    private var compactTaskList: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(CueInColors.divider.opacity(design == .reminders ? 0.35 : 0.7))
                .frame(height: 0.5)
                .padding(.vertical, design == .reminders ? CueInSpacing.xs * 0.5 : CueInSpacing.xs)

            ForEach(block.tasks) { task in
                TaskRowView(task: task, blockAccent: blockTimelineAccent) {
                    onToggleTask(task.id)
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func runningBlockAddTaskButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: CueInSpacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: design == .glass ? 18 : 16, weight: .semibold))
                    .foregroundStyle(blockTimelineAccent)
                Text("Add task")
                    .font(design == .glass ? CueInTypography.bodyMedium : CueInTypography.captionMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, design == .reminders ? CueInSpacing.xs : CueInSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add task to this block")
        .accessibilityHint("Create a new task or choose one from your library")
    }
}

#if os(macOS)
private struct BlockMainInteractionGestureView: View {
    let actions: ScheduleBlockMainRowGestureActions
    let onSwipeChanged: (CGFloat) -> Void
    let onSwipeEnded: (CGFloat, CGFloat) -> Void

    @State private var longPressStarted = false

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        onSwipeChanged(value.translation.width)
                    }
                    .onEnded { value in
                        onSwipeEnded(value.translation.width, value.predictedEndTranslation.width - value.translation.width)
                    }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.25)
                    .onEnded { _ in
                        guard actions.allowsLongPress else { return }
                        longPressStarted = true
                        actions.onBegan(.zero)
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if longPressStarted {
                            actions.onChanged(value.location)
                        }
                    }
                    .onEnded { _ in
                        if longPressStarted {
                            longPressStarted = false
                            actions.onEnded()
                        }
                    }
            )
            .onTapGesture {
                actions.onTapped()
            }
    }
}

private struct HorizontalSwipeGestureView: View {
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat) -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        onChanged(value.translation.width)
                    }
                    .onEnded { value in
                        onEnded(value.translation.width, value.predictedEndTranslation.width - value.translation.width)
                    }
            )
    }
}
#endif

#if os(iOS)
private struct BlockMainInteractionUIKitGestureView: UIViewRepresentable {
    let actions: ScheduleBlockMainRowGestureActions
    let onSwipeChanged: (CGFloat) -> Void
    let onSwipeEnded: (CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        view.addGestureRecognizer(pan)

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.25
        longPress.allowableMovement = 8
        longPress.cancelsTouchesInView = false
        longPress.delaysTouchesBegan = false
        longPress.delaysTouchesEnded = false
        longPress.delegate = context.coordinator
        view.addGestureRecognizer(longPress)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.require(toFail: longPress)
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        context.coordinator.pan = pan
        context.coordinator.longPress = longPress
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.longPress?.isEnabled = actions.allowsLongPress
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: BlockMainInteractionUIKitGestureView
        weak var pan: UIPanGestureRecognizer?
        weak var longPress: UILongPressGestureRecognizer?

        init(parent: BlockMainInteractionUIKitGestureView) {
            self.parent = parent
        }

        @objc func handlePan(_ sender: UIPanGestureRecognizer) {
            let translation = sender.translation(in: sender.view)
            let velocity = sender.velocity(in: sender.view)

            switch sender.state {
            case .began, .changed:
                parent.onSwipeChanged(translation.x)
            case .ended, .cancelled, .failed:
                parent.onSwipeEnded(translation.x, velocity.x)
            case .possible:
                break
            @unknown default:
                break
            }
        }

        @objc func handleLongPress(_ sender: UILongPressGestureRecognizer) {
            let location = sender.location(in: nil)
            switch sender.state {
            case .began:
                parent.actions.onBegan(location)
            case .changed:
                parent.actions.onChanged(location)
            case .ended:
                parent.actions.onEnded()
            case .cancelled, .failed:
                parent.actions.onCancelled()
            case .possible:
                break
            @unknown default:
                break
            }
        }

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            if sender.state == .ended {
                parent.actions.onTapped()
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === pan {
                guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
                let velocity = pan.velocity(in: pan.view)
                return abs(velocity.x) > abs(velocity.y) * 1.15 && abs(velocity.x) > 20
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            isScrollViewGesture(otherGestureRecognizer)
        }

        private func isScrollViewGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            var view = gestureRecognizer.view
            while let current = view {
                if current is UIScrollView {
                    return true
                }
                view = current.superview
            }
            return false
        }
    }
}

private struct HorizontalSwipeUIKitGestureView: UIViewRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        view.addGestureRecognizer(pan)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: HorizontalSwipeUIKitGestureView

        init(parent: HorizontalSwipeUIKitGestureView) {
            self.parent = parent
        }

        @objc func handlePan(_ sender: UIPanGestureRecognizer) {
            let translation = sender.translation(in: sender.view)
            let velocity = sender.velocity(in: sender.view)

            switch sender.state {
            case .began, .changed:
                parent.onChanged(translation.x)
            case .ended, .cancelled, .failed:
                parent.onEnded(translation.x, velocity.x)
            case .possible:
                break
            @unknown default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.15 && abs(velocity.x) > 20
        }
    }
}

private typealias BlockMainInteractionGestureView = BlockMainInteractionUIKitGestureView
private typealias HorizontalSwipeGestureView = HorizontalSwipeUIKitGestureView
#endif

// MARK: - Liquid glass block chrome

/// When **Canvas dots** is on, use the same iOS 26 `glassEffect` + rounded-rect shape as other liquid UI (see `MenuGlassBackground`).
/// Softens and slightly compresses finished blocks without washing out the whole row.
private struct ScheduleBlockCompletedAppearanceModifier: ViewModifier {
    let isCompleted: Bool

    func body(content: Content) -> some View {
        if isCompleted {
            content
                .opacity(0.9)
                .saturation(0.82)
        } else {
            content
        }
    }
}

private struct ScheduleBlockGlassDesignModifier: ViewModifier {
    var useCanvasLiquidGlass: Bool
    let isCurrentBlock: Bool
    let isCompleted: Bool
    let cornerRadius: CGFloat
    let runningPrimary: Color

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        if useCanvasLiquidGlass {
            liquidGlassBody(content: content)
        } else {
            content
                .background(runningBlockWashBackground)
                .clipShape(shape)
                .background(flatGlassFill)
                .glassSurface(cornerRadius: cornerRadius)
        }
    }

    @ViewBuilder
    private var runningBlockWashBackground: some View {
        if isCurrentBlock, !isCompleted {
            shape.fill(CueInColors.scheduleRunningBlockWash(accent: runningPrimary))
        }
    }

    private var flatGlassFill: Color {
        if isCompleted {
            return CueInColors.surfacePrimary.opacity(0.22)
        }
        if isCurrentBlock {
            return CueInColors.scheduleRunningBlockWash(accent: runningPrimary).opacity(0.55)
        }
        return CueInColors.surfacePrimary.opacity(0.4)
    }

    private var liquidGlassTint: Color {
        if isCompleted {
            return Color.white.opacity(0.05)
        }
        if isCurrentBlock {
            return runningPrimary.opacity(CueInThemePreference.current == .light ? 0.20 : 0.24)
        }
        return Color.white.opacity(0.10)
    }

    @ViewBuilder
    private func liquidGlassBody(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content
                .background(runningBlockWashBackground)
                .clipShape(shape)
                .glassEffect(
                    .regular
                        .tint(liquidGlassTint)
                        .interactive(),
                    in: shape
                )
                .overlay {
                    shape
                        .strokeBorder(
                            isCurrentBlock && !isCompleted
                                ? runningPrimary.opacity(0.30)
                                : Color.white.opacity(isCompleted ? 0.08 : 0.16),
                            lineWidth: 0.65
                        )
                }
        } else {
            content
                .background(runningBlockWashBackground)
                .clipShape(shape)
                .background(flatGlassFill)
                .glassSurface(cornerRadius: cornerRadius)
        }
    }
}
