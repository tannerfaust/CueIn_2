import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - TodayTodoView
/// Task-led Today presentation backed by the shared execution pool (`TasksStore.todayTasks`).

struct TodayTodoView: View {
    let store: TasksStore
    let onOpenTask: (UUID) -> Void

    @AppStorage(TodayDisplayPreferences.todoTaskBlockStyle) private var blockStyleRaw
        = TodayDisplayPreferences.TodoTaskBlockStyle.listClassic.rawValue
    @AppStorage(TodayDisplayPreferences.todoRowDensity) private var rowDensityRaw
        = TodayDisplayPreferences.TodoRowDensity.regular.rawValue
    @AppStorage(TodayDisplayPreferences.todoShowCompletedSection) private var showCompletedSection = true
    @State private var isTodoReordering = false
    @State private var viewportFrame: CGRect = .zero
    #if os(iOS)
    @State private var todoScrollView: UIScrollView?
    #endif

    private var blockStyle: TodayDisplayPreferences.TodoTaskBlockStyle {
        TodayDisplayPreferences.migratedTodoTaskBlockStyle(from: blockStyleRaw)
    }

    private var rowDensity: TodayDisplayPreferences.TodoRowDensity {
        TodayDisplayPreferences.migratedTodoRowDensity(from: rowDensityRaw)
    }

    private var tasks: [TaskItem] {
        store.todayTasks
    }

    private var openTasks: [TaskItem] {
        tasks.filter { !$0.isCompleted }
    }

    private var completedTasks: [TaskItem] {
        tasks.filter(\.isCompleted)
    }

    private var totalMinutes: Int {
        openTasks.reduce(0) { $0 + $1.plannedMinutes }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: sectionStackSpacing) {
                TodayTodoHeader(
                    openCount: openTasks.count,
                    completedCount: completedTasks.count,
                    totalMinutes: totalMinutes
                )

                if tasks.isEmpty {
                    TodayTodoEmptyState()
                } else {
                    TodayTodoTaskGroup(
                        title: nil,
                        tasks: openTasks,
                        store: store,
                        blockStyle: blockStyle,
                        rowDensity: rowDensity,
                        viewportFrame: viewportFrame,
                        isReordering: $isTodoReordering,
                        onOpenTask: onOpenTask,
                        onAutoScroll: { request in
                            autoScrollTodoList(by: request.deltaY)
                        }
                    )

                    if showCompletedSection, !completedTasks.isEmpty {
                        TodayTodoTaskGroup(
                            title: "Done",
                            tasks: completedTasks,
                            store: store,
                            blockStyle: blockStyle,
                            rowDensity: rowDensity,
                            viewportFrame: viewportFrame,
                            isReordering: .constant(false),
                            onOpenTask: onOpenTask,
                            onAutoScroll: { _ in }
                        )
                    }
                }
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)
            .padding(.top, CueInSpacing.sm)
            .padding(.bottom, CueInLayout.scrollBottomInset)
            .background {
                #if os(iOS)
                TodayTodoScrollViewResolver(scrollView: $todoScrollView)
                #else
                Color.clear
                #endif
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: TodayTodoViewportPreferenceKey.self,
                    value: geo.frame(in: .global)
                )
            }
        }
        .onPreferenceChange(TodayTodoViewportPreferenceKey.self) { frame in
            viewportFrame = frame
        }
        .scrollDisabled(isTodoReordering)
        .background(CueInColors.background)
    }

    private var sectionStackSpacing: CGFloat {
        switch blockStyle {
        case .listClassic:
            return CueInSpacing.md
        case .frames:
            return CueInSpacing.sm
        }
    }

    private func autoScrollTodoList(by deltaY: CGFloat) {
        #if os(iOS)
        guard let scrollView = todoScrollView,
              abs(deltaY) > 0.5
        else { return }

        let minimumY = -scrollView.adjustedContentInset.top
        let maximumY = max(
            minimumY,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        let current = scrollView.contentOffset
        let nextY = min(max(current.y + deltaY, minimumY), maximumY)
        guard abs(nextY - current.y) > 0.5 else { return }

        scrollView.setContentOffset(
            CGPoint(x: current.x, y: nextY),
            animated: false
        )
        #endif
    }
}

private struct TodayTodoViewportPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

#if os(iOS)
private struct TodayTodoScrollViewResolver: UIViewRepresentable {
    @Binding var scrollView: UIScrollView?

    func makeUIView(context: Context) -> UIView {
        let view = ResolverView()
        view.onResolve = { scrollView = $0 }
        return view
    }

    func updateUIView(_ uiView: UIView, context _: Context) {
        (uiView as? ResolverView)?.resolveSoon()
    }

    final class ResolverView: UIView {
        var onResolve: ((UIScrollView?) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            resolveSoon()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            resolveSoon()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            resolveSoon()
        }

        func resolveSoon() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                onResolve?(enclosingScrollView)
            }
        }
    }
}

private extension UIView {
    var enclosingScrollView: UIScrollView? {
        var current = superview
        while let view = current {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }
}
#endif

// MARK: - TodayTodoHeader

private struct TodayTodoHeader: View {
    let openCount: Int
    let completedCount: Int
    let totalMinutes: Int

    @AppStorage(TodayDisplayPreferences.todoViewShowInfoBlock) private var showInfoBlock = true
    @AppStorage(TodayDisplayPreferences.todoSummaryPlacement) private var summaryPlacementRaw
        = TodayDisplayPreferences.TodoSummaryPlacement.inList.rawValue
    @AppStorage(TodayDisplayPreferences.todoSummaryShowPlannedTime) private var summaryShowPlannedTime = true
    @AppStorage(TodayDisplayPreferences.todoSummaryShowMetricPills) private var summaryShowMetricPills = true

    private var summaryPlacement: TodayDisplayPreferences.TodoSummaryPlacement {
        TodayDisplayPreferences.migratedTodoSummaryPlacement(from: summaryPlacementRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            if showInfoBlock, summaryPlacement == .inList {
                summaryListPill
            }
        }
        .padding(.bottom, CueInSpacing.xs)
    }

    private var summaryListPill: some View {
        HStack(alignment: .center, spacing: CueInSpacing.md) {
            if summaryShowPlannedTime, summaryShowMetricPills {
                plannedColumn
                Capsule()
                    .fill(CueInColors.divider.opacity(0.5))
                    .frame(width: 1, height: 26)
                metricPills
            } else if summaryShowPlannedTime {
                plannedColumn
                Spacer(minLength: 0)
            } else if summaryShowMetricPills {
                Spacer(minLength: 0)
                metricPills
                Spacer(minLength: 0)
            } else {
                Text("Turn on planned time or counts in Settings, or hide the summary.")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.055))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(CueInColors.cardBorder.opacity(0.45), lineWidth: 0.5)
        }
        .modifier(CueInStableGlassCapsuleModifier())
    }

    private var plannedColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Planned")
                .font(CueInTypography.micro)
                .foregroundStyle(CueInColors.textTertiary)
            Text(TodayDisplayPreferences.formatTodoPlannedMinutesLine(totalMinutes))
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(CueInColors.textPrimary)
        }
        .frame(minWidth: 0, alignment: .leading)
    }

    private var metricPills: some View {
        HStack(spacing: CueInSpacing.sm) {
            TodayTodoMetricPill(value: "\(openCount)", label: "open")
            TodayTodoMetricPill(value: "\(completedCount)", label: "done")
            TodayTodoMetricPill(value: "\(openCount + completedCount)", label: "total")
        }
    }
}

// MARK: - TodayTodoMetricPill

private struct TodayTodoMetricPill: View {
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(value)
                .font(CueInTypography.captionMedium)
                .foregroundStyle(CueInColors.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(CueInTypography.micro)
                .foregroundStyle(CueInColors.textTertiary)
        }
        .frame(height: 28)
        .padding(.horizontal, 9)
        .background(Color.white.opacity(0.06))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(CueInColors.cardBorder.opacity(0.4), lineWidth: 0.5)
        }
        .clipShape(Capsule(style: .continuous))
    }
}

private enum TodayTodoAutoScrollDirection: Hashable {
    case up
    case down
}

private struct TodayTodoAutoScrollRequest {
    let deltaY: CGFloat
}

@MainActor
private final class TodayTodoAutoScrollDriver: NSObject {
    private var timer: Timer?
    private var step: (() -> Bool)?

    func start(step: @escaping () -> Bool) {
        self.step = step
        guard timer == nil else { return }

        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        step = nil
    }

    deinit {
        timer?.invalidate()
    }

    @objc private func tick() {
        if step?() != true {
            stop()
        }
    }
}

private enum TodayTodoFramesStyle {
    /// Rounded “card” corners (clearly rounder than the old 8pt chip radius).
    static let cornerRadius: CGFloat = CueInSpacing.cardRadius
}

// MARK: - TodayTodoTaskGroup

private struct TodayTodoTaskGroup: View {
    /// When `nil`, no section header is shown (main open-task list).
    let title: String?
    let tasks: [TaskItem]
    let store: TasksStore
    let blockStyle: TodayDisplayPreferences.TodoTaskBlockStyle
    let rowDensity: TodayDisplayPreferences.TodoRowDensity
    let viewportFrame: CGRect
    @Binding var isReordering: Bool
    let onOpenTask: (UUID) -> Void
    let onAutoScroll: (TodayTodoAutoScrollRequest) -> Void

    @AppStorage(TodayDisplayPreferences.todoShowSectionCountBadge) private var showSectionCountBadge = true
    @AppStorage(TodayDisplayPreferences.todoRowShowCheckbox) private var rowShowCheckbox = true

    @State private var liveFrames: [UUID: CGRect] = [:]
    @State private var frozenFrames: [UUID: CGRect] = [:]
    @State private var containerFrame: CGRect = .zero
    @State private var visualTaskIDs: [UUID] = []
    @State private var draggedTaskID: UUID?
    @State private var dragGrabOffsetY: CGFloat = 0
    @State private var dragCenterY: CGFloat?
    @State private var dragStartCenterY: CGFloat?
    @State private var hasActiveDragStarted = false
    @State private var dragStartOrderIDs: [UUID] = []
    @State private var pendingPreferenceFrames: [UUID: CGRect] = [:]
    @State private var hasScheduledPreferenceFlush = false
    @State private var autoScrollDirection: TodayTodoAutoScrollDirection?
    @State private var autoScrollDeltaY: CGFloat = 0
    @State private var autoScrollDriver = TodayTodoAutoScrollDriver()

    private struct TaskFramePreferenceKey: PreferenceKey {
        static var defaultValue: [UUID: CGRect] = [:]
        static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }

    private struct ContainerFramePreferenceKey: PreferenceKey {
        static var defaultValue: CGRect = .zero
        static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
            value = nextValue()
        }
    }

    /// Undo + ordering key for deletes (matches Tasks-tab pool behavior).
    private var listKey: String { "today:todo" }
    private var allowsReordering: Bool { title == nil && tasks.count > 1 }

    private var orderedTasks: [TaskItem] {
        allowsReordering ? store.orderedTasks(tasks, listKey: listKey) : tasks
    }

    private var orderedTaskIDs: [UUID] {
        orderedTasks.map(\.id)
    }

    private var displayTasks: [TaskItem] {
        let ids = visualTaskIDs.isEmpty ? orderedTaskIDs : visualTaskIDs
        guard Set(ids) == Set(orderedTaskIDs), ids.count == orderedTaskIDs.count else {
            return orderedTasks
        }
        let byID = Dictionary(uniqueKeysWithValues: orderedTasks.map { ($0.id, $0) })
        let ordered = ids.compactMap { byID[$0] }
        return ordered.count == orderedTasks.count ? ordered : orderedTasks
    }

    private var reorderAnimation: Animation {
        .interactiveSpring(response: 0.16, dampingFraction: 0.92, blendDuration: 0.01)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                if let title {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CueInColors.textTertiary)
                        Spacer(minLength: 8)
                        if showSectionCountBadge {
                            Text("\(tasks.count)")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(CueInColors.textTertiary.opacity(0.85))
                                .monospacedDigit()
                        }
                    }
                    .padding(.bottom, CueInSpacing.sm)
                }

                taskListBody
            }

            dragOverlay
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: ContainerFramePreferenceKey.self,
                    value: geo.frame(in: .global)
                )
            }
        }
        .onPreferenceChange(ContainerFramePreferenceKey.self) { frame in
            handleContainerFrameChanged(frame)
        }
        .onPreferenceChange(TaskFramePreferenceKey.self) { frames in
            pendingPreferenceFrames = frames
            schedulePreferenceFrameFlushIfNeeded()
        }
        .onAppear {
            syncVisualOrder(force: true)
        }
        .onChange(of: orderedTaskIDs) { _, _ in
            if draggedTaskID == nil {
                syncVisualOrder(force: true)
            }
        }
    }

    @ViewBuilder
    private var dragOverlay: some View {
        if let draggedTaskID,
           let task = orderedTasks.first(where: { $0.id == draggedTaskID }),
           let frame = frozenFrames[draggedTaskID],
           let centerY = dragCenterY,
           hasActiveDragStarted,
           containerFrame != .zero {
            cellContent(for: task, allowsSwipe: false, allowsReorder: false)
                .frame(width: frame.width)
                .position(
                    x: frame.midX - containerFrame.minX,
                    y: centerY - containerFrame.minY
                )
                .scaleEffect(1.02)
                .shadow(color: Color.black.opacity(0.24), radius: 18, y: 10)
                .zIndex(10_000)
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.985).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func cellContent(
        for task: TaskItem,
        allowsSwipe: Bool,
        allowsReorder: Bool
    ) -> some View {
        switch blockStyle {
        case .listClassic:
            rowContent(for: task, allowsSwipe: allowsSwipe, allowsReorder: allowsReorder)
        case .frames:
            rowContent(for: task, allowsSwipe: allowsSwipe, allowsReorder: allowsReorder)
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: TodayTodoFramesStyle.cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.048))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: TodayTodoFramesStyle.cornerRadius, style: .continuous)
                        .strokeBorder(CueInColors.cardBorder.opacity(0.42), lineWidth: 0.5)
                }
        }
    }

    private func rowContent(
        for task: TaskItem,
        allowsSwipe: Bool,
        allowsReorder: Bool
    ) -> some View {
        TodayTodoTaskRow(
            task: task,
            store: store,
            onOpen: { onOpenTask(task.id) },
            onDelete: { deleteTaskWithUndo(task) },
            allowsSwipe: allowsSwipe && draggedTaskID == nil,
            reorderActions: allowsReorder ? reorderActions(for: task) : nil
        )
    }

    private func reorderableCell<Content: View>(
        for task: TaskItem,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isPlaceholder = draggedTaskID == task.id && hasActiveDragStarted
        return content()
            .id(task.id)
            .background(frameReader(for: task.id))
            .opacity(isPlaceholder ? 0.18 : 1)
            .allowsHitTesting(draggedTaskID == nil || draggedTaskID == task.id)
            .zIndex(draggedTaskID == task.id ? 1000 : 0)
            .animation(reorderAnimation, value: visualTaskIDs)
    }

    private func reorderActions(for task: TaskItem) -> TodayTodoRowReorderActions {
        TodayTodoRowReorderActions(
            onBegan: { handleDragBegan(for: task, at: $0) },
            onChanged: { handleDragChanged(for: task, at: $0) },
            onEnded: { handleDragEnded(for: task) },
            onCancelled: { handleDragCancelled() },
            onTapped: { onOpenTask(task.id) }
        )
    }

    private func frameReader(for taskID: UUID) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: TaskFramePreferenceKey.self,
                value: [taskID: geo.frame(in: .global)]
            )
        }
    }

    private func hasCompleteFrameSet(_ frames: [UUID: CGRect]) -> Bool {
        guard !orderedTaskIDs.isEmpty else { return true }
        return orderedTaskIDs.allSatisfy { frames[$0] != nil }
    }

    private func baselineFramesForCurrentOrder() -> [UUID: CGRect] {
        if hasCompleteFrameSet(liveFrames),
           frameOrderMatchesCurrentTasks(liveFrames) {
            return liveFrames
        }
        return synthesizedFrameSetForCurrentOrder(from: liveFrames)
    }

    private func frameOrderMatchesCurrentTasks(_ frames: [UUID: CGRect]) -> Bool {
        guard hasCompleteFrameSet(frames) else { return false }
        let measuredOrder = orderedTaskIDs.sorted { lhs, rhs in
            guard let left = frames[lhs], let right = frames[rhs] else { return false }
            if abs(left.minY - right.minY) > 0.5 {
                return left.minY < right.minY
            }
            return left.minX < right.minX
        }
        return measuredOrder == orderedTaskIDs
    }

    private func synthesizedFrameSetForCurrentOrder(from sourceFrames: [UUID: CGRect]) -> [UUID: CGRect] {
        guard !orderedTaskIDs.isEmpty else { return [:] }

        let fallbackFrame = sourceFrames.values.first ?? CGRect(x: 0, y: 0, width: 1, height: 58)
        let startX = sourceFrames.values.map(\.minX).min() ?? fallbackFrame.minX
        let startY = sourceFrames.values.map(\.minY).min() ?? fallbackFrame.minY
        let fallbackWidth = max(fallbackFrame.width, 1)
        let fallbackHeight = max(fallbackFrame.height, 1)
        let spacing: CGFloat = {
            switch blockStyle {
            case .frames:
                return Self.framesInterRowSpacing
            case .listClassic:
                return 0
            }
        }()

        var cursorY = startY
        var synthesized: [UUID: CGRect] = [:]
        for id in orderedTaskIDs {
            let source = sourceFrames[id]
            let height = max(source?.height ?? fallbackHeight, 1)
            let width = max(source?.width ?? fallbackWidth, 1)
            synthesized[id] = CGRect(
                x: source?.minX ?? startX,
                y: cursorY,
                width: width,
                height: height
            )
            cursorY += height + spacing
        }
        return synthesized
    }

    private func handleContainerFrameChanged(_ frame: CGRect) {
        let previousFrame = containerFrame
        containerFrame = frame

        guard draggedTaskID != nil,
              previousFrame != .zero,
              frame != .zero
        else { return }

        let deltaY = frame.minY - previousFrame.minY
        guard abs(deltaY) > 0.5 else { return }

        frozenFrames = frozenFrames.mapValues { $0.offsetBy(dx: 0, dy: deltaY) }
        if let sourceID = draggedTaskID,
           let centerY = dragCenterY {
            updateVisualOrder(sourceID: sourceID, centerY: centerY)
        }
    }

    private func handleDragBegan(for task: TaskItem, at location: CGPoint) {
        guard allowsReordering else { return }
        if draggedTaskID != task.id {
            syncVisualOrder(force: true)
            let baseline = baselineFramesForCurrentOrder()
            guard let frame = baseline[task.id] else { return }

            CueInHaptics.impact(.light)
            isReordering = true
            frozenFrames = baseline
            draggedTaskID = task.id
            dragStartOrderIDs = orderedTaskIDs
            dragGrabOffsetY = location.y - frame.midY
            setDragCenterY(frame.midY)
            dragStartCenterY = frame.midY
            hasActiveDragStarted = true
            updateAutoScrollDirection(for: frame.midY)
        }
    }

    private func handleDragChanged(for task: TaskItem, at location: CGPoint) {
        guard draggedTaskID == task.id else { return }
        let centerY = location.y - dragGrabOffsetY
        setDragCenterY(centerY)
        let startCenterY = dragStartCenterY ?? centerY
        guard abs(centerY - startCenterY) > 4 else { return }
        updateVisualOrder(sourceID: task.id, centerY: centerY)
        updateAutoScrollDirection(for: centerY)
    }

    private func setDragCenterY(_ centerY: CGFloat) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            dragCenterY = centerY
        }
    }

    private func handleDragEnded(for task: TaskItem) {
        guard draggedTaskID == task.id else { return }
        let didCommitMove = commitVisualOrder(sourceID: task.id)

        withAnimation(reorderAnimation) {
            clearDragState()
            if !didCommitMove {
                syncVisualOrder(force: true)
            }
        }
    }

    private func handleDragCancelled() {
        withAnimation(reorderAnimation) {
            clearDragState()
            syncVisualOrder(force: true)
        }
    }

    private func updateAutoScrollDirection(for centerY: CGFloat) {
        guard viewportFrame != .zero,
              containerFrame != .zero
        else {
            autoScrollDirection = nil
            autoScrollDeltaY = 0
            return
        }

        let activationDistance: CGFloat = 150
        let topTrigger = max(viewportFrame.minY + activationDistance, containerFrame.minY + 44)
        let bottomTrigger = min(viewportFrame.maxY - activationDistance, containerFrame.maxY - 44)

        if centerY < topTrigger {
            let intensity = min(1, max(0, (topTrigger - centerY) / activationDistance))
            setAutoScroll(direction: .up, deltaY: -(7 + 25 * intensity))
        } else if centerY > bottomTrigger {
            let intensity = min(1, max(0, (centerY - bottomTrigger) / activationDistance))
            setAutoScroll(direction: .down, deltaY: 7 + 25 * intensity)
        } else {
            setAutoScroll(direction: nil, deltaY: 0)
        }
    }

    private func setAutoScroll(direction: TodayTodoAutoScrollDirection?, deltaY: CGFloat) {
        autoScrollDirection = direction
        autoScrollDeltaY = deltaY

        if let direction {
            autoScrollDriver.start {
                performAutoScrollStep(direction: direction)
            }
        } else {
            autoScrollDriver.stop()
        }
    }

    private func performAutoScrollStep(direction: TodayTodoAutoScrollDirection) -> Bool {
        guard let sourceID = draggedTaskID,
              hasActiveDragStarted,
              visualTaskIDs.count > 1,
              visualTaskIDs.contains(sourceID)
        else { return false }

        let deltaY = direction == .up ? min(autoScrollDeltaY, -1) : max(autoScrollDeltaY, 1)
        onAutoScroll(TodayTodoAutoScrollRequest(deltaY: deltaY))
        if let centerY = dragCenterY {
            updateVisualOrder(sourceID: sourceID, centerY: centerY)
        }
        return true
    }

    private func updateVisualOrder(sourceID: UUID, centerY: CGFloat) {
        let baselineOrder = orderedTaskIDs
        let nextOrder = ReorderEngine.visualOrder(
            orderedIDs: baselineOrder,
            baselineFrames: frozenFrames,
            draggedID: sourceID,
            centerY: centerY
        )

        guard nextOrder.count == baselineOrder.count,
              Set(nextOrder) == Set(baselineOrder),
              nextOrder != visualTaskIDs
        else { return }

        withAnimation(reorderAnimation) {
            visualTaskIDs = nextOrder
        }
        CueInHaptics.impact(.light)
    }

    private func commitVisualOrder(sourceID: UUID) -> Bool {
        guard visualTaskIDs.count == orderedTaskIDs.count,
              Set(visualTaskIDs) == Set(orderedTaskIDs),
              visualTaskIDs != orderedTaskIDs
        else { return false }

        let previousOrder = dragStartOrderIDs.isEmpty ? orderedTaskIDs : dragStartOrderIDs
        let previousPriority = store.tasks.first(where: { $0.id == sourceID })?.priority
        let wasPrioritySortingActive = !store.hasCustomTaskOrder(listKey: listKey)
        store.setTaskOrder(listKey: listKey, orderedIDs: visualTaskIDs)
        let priorityChange = wasPrioritySortingActive
            ? adjustedPriorityIfNeeded(
                movedID: sourceID,
                orderedIDs: visualTaskIDs,
                previousPriority: previousPriority
            )
            : nil
        TodayViewModel.shared.syncExecutionTimelineAfterExternalTaskEdit()

        if let priorityChange {
            showPriorityAdjustedToast(
                taskID: sourceID,
                previousPriority: priorityChange,
                previousOrder: previousOrder
            )
        }
        return true
    }

    private func adjustedPriorityIfNeeded(
        movedID: UUID,
        orderedIDs: [UUID],
        previousPriority: TaskPriority?
    ) -> TaskPriority? {
        guard let movedIndex = orderedIDs.firstIndex(of: movedID),
              let oldPriority = previousPriority
        else { return nil }

        let byID = Dictionary(uniqueKeysWithValues: store.tasks.map { ($0.id, $0) })
        let previousWeight = orderedIDs[..<movedIndex]
            .reversed()
            .compactMap { byID[$0]?.priority.sortWeight }
            .first ?? TaskPriority.urgent.sortWeight
        let nextWeight = orderedIDs.dropFirst(movedIndex + 1)
            .compactMap { byID[$0]?.priority.sortWeight }
            .first ?? TaskPriority.normal.sortWeight
        let lowerBound = min(previousWeight, nextWeight)
        let upperBound = max(previousWeight, nextWeight)
        let clampedWeight = min(max(oldPriority.sortWeight, lowerBound), upperBound)
        guard let adjustedPriority = TaskPriority.priority(sortWeight: clampedWeight),
              adjustedPriority != oldPriority
        else { return nil }

        store.setTaskPriority(id: movedID, priority: adjustedPriority)
        return oldPriority
    }

    private func showPriorityAdjustedToast(
        taskID: UUID,
        previousPriority: TaskPriority,
        previousOrder: [UUID]
    ) {
        CueInToastCenter.shared.show(
            icon: "arrow.up.arrow.down",
            title: "Priority changed",
            message: "The priority of the block was changed to accommodate the new layout.",
            tint: CueInColors.accentFixed
        ) {
            store.setTaskPriority(id: taskID, priority: previousPriority)
            store.setTaskOrder(listKey: listKey, orderedIDs: previousOrder)
            TodayViewModel.shared.syncExecutionTimelineAfterExternalTaskEdit()
        }
    }

    private func clearDragState() {
        draggedTaskID = nil
        isReordering = false
        hasActiveDragStarted = false
        frozenFrames = [:]
        dragGrabOffsetY = 0
        dragCenterY = nil
        dragStartCenterY = nil
        dragStartOrderIDs = []
        autoScrollDirection = nil
        autoScrollDeltaY = 0
        autoScrollDriver.stop()
    }

    private func syncVisualOrder(force: Bool = false) {
        let ids = orderedTaskIDs
        guard force || visualTaskIDs.isEmpty || Set(visualTaskIDs) != Set(ids) else { return }
        visualTaskIDs = ids
    }

    private func schedulePreferenceFrameFlushIfNeeded() {
        guard !hasScheduledPreferenceFlush else { return }
        hasScheduledPreferenceFlush = true
        DispatchQueue.main.async {
            hasScheduledPreferenceFlush = false
            let frames = pendingPreferenceFrames
            guard draggedTaskID == nil,
                  hasCompleteFrameSet(frames),
                  frameOrderMatchesCurrentTasks(frames),
                  liveFrames != frames
            else { return }
            liveFrames = frames
        }
    }

    @ViewBuilder
    private var taskListBody: some View {
        switch blockStyle {
        case .listClassic:
            listClassicStack
        case .frames:
            framesStack
        }
    }

    private var framesStack: some View {
        VStack(spacing: Self.framesInterRowSpacing) {
            ForEach(displayTasks) { task in
                reorderableCell(for: task) {
                    cellContent(for: task, allowsSwipe: true, allowsReorder: allowsReordering)
                }
            }
        }
    }

    /// Tight vertical rhythm between frame cards.
    private static let framesInterRowSpacing: CGFloat = 2

    private var listClassicStack: some View {
        VStack(spacing: 0) {
            ForEach(Array(displayTasks.enumerated()), id: \.element.id) { index, task in
                VStack(alignment: .leading, spacing: 0) {
                    reorderableCell(for: task) {
                        cellContent(for: task, allowsSwipe: true, allowsReorder: allowsReordering)
                    }

                    if index < displayTasks.count - 1 {
                        Rectangle()
                            .fill(CueInColors.divider.opacity(0.45))
                            .frame(height: 1)
                            .padding(.leading, rowShowCheckbox ? 32 : 8)
                    }
                }
            }
        }
    }

    private func deleteTaskWithUndo(_ task: TaskItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            store.deleteTask(task.id)
        }
        TodayViewModel.shared.syncExecutionTimelineAfterExternalTaskEdit()
        CueInToastCenter.shared.show(
            icon: task.isNotionImported ? "archivebox.fill" : "trash.fill",
            title: task.isNotionImported ? "Archived in CueIn" : "Task deleted",
            message: task.isNotionImported ? "Notion task stays in Notion" : task.title,
            tint: Color(hex: 0x64A8FF)
        ) {
            if task.isNotionImported {
                store.updateTask(task)
            } else {
                store.restoreTask(task, listKey: listKey)
            }
            if Calendar.current.isDateInToday(task.scheduledDate ?? .distantPast) {
                TodayViewModel.shared.enqueuePlannerTask(task)
            }
            TodayViewModel.shared.syncExecutionTimelineAfterExternalTaskEdit()
        }
    }
}

// MARK: - Reorder engine (uses shared ReorderEngine)


private extension TaskPriority {
    static func priority(sortWeight: Int) -> TaskPriority? {
        allCases.first { $0.sortWeight == sortWeight }
    }
}

// MARK: - TodayTodoEmptyState

private struct TodayTodoEmptyState: View {
    @AppStorage(TodayDisplayPreferences.todoShowEmptyStateMessage) private var showEmptyStateMessage = true

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            Image(systemName: "tray")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(CueInColors.textTertiary)

            Text("No tasks in the execution pool")
                .font(CueInTypography.headline)
                .foregroundStyle(CueInColors.textPrimary)

            if showEmptyStateMessage {
                Text("Queue tasks for today from the Tasks tab and they will appear here.")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CueInSpacing.lg)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CueInColors.surfacePrimary.opacity(0.72))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(CueInColors.cardBorder, lineWidth: 0.5)
        }
    }
}

#Preview {
    ZStack {
        CueInColors.background.ignoresSafeArea()
        TodayTodoView(
            store: .shared,
            onOpenTask: { _ in }
        )
    }
    .cueInPreferredColorScheme()
}
