import SwiftUI

struct ScheduleBlockTimelineView: View {
    let blocks: [DayBlock]
    let currentBlockID: UUID?
    var scheduleDesign: TodayDisplayPreferences.ScheduleDesign = .glass
    var useCanvasLiquidGlass: Bool = false
    /// When set, live block timers use this instant instead of the wall clock (formula run paused).
    var frozenLiveProgressDate: Date? = nil
    let showsScheduledTime: Bool
    let showsStartTime: Bool
    let showsDuration: Bool
    let showsTimeRange: Bool
    let showsFinishControl: Bool
    let showsCompletedToggle: Bool
    let isLiveRun: Bool
    let timerStyle: TodayDisplayPreferences.ScheduleBlockTimerStyle
    let showsTimerSeconds: Bool
    @Binding var draggedBlockID: UUID?
    let canRearrangeBlock: (UUID) -> Bool
    let canUseBlockContextMenu: (UUID) -> Bool
    let canDeleteFromContextMenu: (UUID) -> Bool
    let onMoveBlock: (UUID, UUID?) -> Bool
    let onToggleTask: (UUID, UUID) -> Void
    let onCompleteBlock: (UUID) -> Void
    let onFinishBlockKeepingPending: (UUID) -> Void
    let onRevertCompletedBlock: (UUID) -> Void
    let onContextEdit: (DayBlock) -> Void
    let onContextAddTask: (UUID) -> Void
    let onContextRearrange: (UUID) -> Void
    let onContextDelete: (UUID) -> Void
    let onSwipeCommitDelete: (UUID) -> Void
    let isJiggleRearrangeMode: Bool

    // MARK: - Drag State
    @State private var liveFrames: [UUID: CGRect] = [:]
    @State private var frozenFrames: [UUID: CGRect] = [:]
    @State private var containerFrame: CGRect = .zero
    @State private var visualBlockIDs: [UUID] = []
    @State private var dragGrabOffsetY: CGFloat = 0
    @State private var dragCenterY: CGFloat?
    @State private var dragStartCenterY: CGFloat?
    @State private var hasActiveDragStarted = false
    @State private var pendingPreferenceFrames: [UUID: CGRect] = [:]
    @State private var hasScheduledPreferenceFlush = false

    private struct BlockFramePreferenceKey: PreferenceKey {
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

    private var blockIDs: [UUID] {
        blocks.map(\.id)
    }

    private var blockStackSpacing: CGFloat {
        switch scheduleDesign {
        case .glass: return 10
        case .reminders: return 0
        case .agenda: return 4
        }
    }

    private var reorderAnimation: Animation {
        .interactiveSpring(response: 0.24, dampingFraction: 0.88, blendDuration: 0.02)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            blockStack
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.top, CueInSpacing.sm)
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
                containerFrame = frame
            }
            .onPreferenceChange(BlockFramePreferenceKey.self) { frames in
                pendingPreferenceFrames = frames
                schedulePreferenceFrameFlushIfNeeded()
            }
            .onAppear {
                syncVisualOrder(force: true)
            }
            .onChange(of: blockIDs) { _, _ in
                if draggedBlockID == nil {
                    syncVisualOrder(force: true)
                }
            }
            .onChange(of: draggedBlockID) { _, newValue in
                if newValue == nil {
                    frozenFrames = [:]
                    dragGrabOffsetY = 0
                    dragCenterY = nil
                    dragStartCenterY = nil
                    withAnimation(reorderAnimation) {
                        hasActiveDragStarted = false
                    }
                }
            }
    }

    @ViewBuilder
    private var blockStack: some View {
        if scheduleDesign == .glass, #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: blockStackSpacing) {
                blockRows
            }
        } else {
            blockRows
        }
    }

    @ViewBuilder
    private var blockRows: some View {
        let visibleBlocks = displayBlocks
        VStack(alignment: .leading, spacing: blockStackSpacing) {
            ForEach(Array(visibleBlocks.enumerated()), id: \.element.id) { index, block in
                let isDragged = draggedBlockID == block.id
                
                VStack(alignment: .leading, spacing: 0) {
                    if showsScheduledTime, index > 0 {
                        if scheduleDesign.usesListHairlinesBetweenBlocks {
                            hairlineListConnector(from: visibleBlocks[index - 1], to: block)
                        } else {
                            connector(from: visibleBlocks[index - 1], to: block)
                        }
                    }

                    row(for: block, index: index)
                        .id(block.id)
                }
                .zIndex(isDragged ? 1000 : Double(visibleBlocks.count - index))
                .animation(reorderAnimation, value: visualBlockIDs)
            }
        }
    }

    @ViewBuilder
    private func row(for block: DayBlock, index: Int) -> some View {
        let isPlaceholder = draggedBlockID == block.id && hasActiveDragStarted
        let overlayReady = isDragOverlayReady(for: block.id)
        let canRearrange = canRearrangeBlock(block.id)
        let row = card(for: block)
            .environment(
                \.scheduleBlockMainRowGesture,
                 ScheduleBlockMainRowGestureActions(
                    allowsLongPress: canRearrange,
                    onBegan: { if canRearrange { handleDragBegan(for: block, at: $0) } },
                    onChanged: { if canRearrange { handleDragChanged(for: block, at: $0) } },
                    onEnded: { if canRearrange { handleDragEnded(for: block) } },
                    onCancelled: { if canRearrange { handleDragCancelled() } },
                    onTapped: { onContextEdit(block) }
                 )
            )
            .background(frameReader(for: block.id))
            .accessibilityHidden(isPlaceholder)

        if isPlaceholder, overlayReady {
            row.opacity(0.001)
                .allowsHitTesting(false)
        } else {
            row
        }
    }

    private func card(for block: DayBlock) -> some View {
        let isDragged = draggedBlockID == block.id
        
        return ScheduleBlockCardView(
            block: block,
            isCurrentBlock: block.id == currentBlockID,
            design: scheduleDesign,
            useCanvasLiquidGlass: useCanvasLiquidGlass,
            frozenLiveProgressDate: frozenLiveProgressDate,
            showsStartTime: showsStartTime,
            showsDuration: showsDuration,
            showsTimeRange: showsTimeRange,
            showsFinishControl: showsFinishControl,
            showsCompletedToggle: showsCompletedToggle,
            isLiveRun: isLiveRun,
            timerStyle: timerStyle,
            showsTimerSeconds: showsTimerSeconds,
            onCompleteBlock: { onCompleteBlock(block.id) },
            onFinishBlockKeepingPending: { onFinishBlockKeepingPending(block.id) },
            onRevertCompletedBlock: { onRevertCompletedBlock(block.id) },
            onToggleTask: { onToggleTask(block.id, $0) },
            onEdit: { onContextEdit(block) },
            onDelete: { onContextDelete(block.id) }
        )
        .scaleEffect(isDragged && hasActiveDragStarted ? 1.045 : 1.0)
        .offset(y: isDragged && hasActiveDragStarted ? -2 : 0)
        .shadow(
            color: Color.black.opacity(isDragged && hasActiveDragStarted ? 0.34 : 0),
            radius: isDragged && hasActiveDragStarted ? 18 : 0,
            y: isDragged && hasActiveDragStarted ? 10 : 0
        )
        .animation(reorderAnimation, value: isDragged && hasActiveDragStarted)
    }

    @ViewBuilder
    private var dragOverlay: some View {
        if let draggedID = draggedBlockID,
           let block = blocks.first(where: { $0.id == draggedID }),
           let frame = frozenFrames[draggedID],
           let centerY = dragCenterY,
           hasActiveDragStarted,
           containerFrame != .zero {
            card(for: block)
                .frame(width: frame.width)
                .position(
                    x: frame.midX - containerFrame.minX,
                    y: centerY - containerFrame.minY
                )
                .zIndex(10_000)
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.985).combined(with: .opacity))
        }
    }

    private var displayBlocks: [DayBlock] {
        let ids = visualBlockIDs.isEmpty ? blockIDs : visualBlockIDs
        guard Set(ids) == Set(blockIDs), ids.count == blockIDs.count else { return blocks }

        let byID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
        let ordered = ids.compactMap { byID[$0] }
        return ordered.count == blocks.count ? ordered : blocks
    }

    private func frameReader(for blockID: UUID) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: BlockFramePreferenceKey.self,
                value: [blockID: geo.frame(in: .global)]
            )
        }
    }

    // MARK: - Overlay Reorder Logic
    
    private func handleDragBegan(for block: DayBlock, at location: CGPoint) {
        if draggedBlockID != block.id {
            syncVisualOrder(force: true)
            let baseline = baselineFramesForCurrentOrder()
            guard let frame = baseline[block.id] else { return }

            CueInHaptics.impact(.light)
            frozenFrames = baseline
            draggedBlockID = block.id
            dragGrabOffsetY = location.y - frame.midY
            dragCenterY = frame.midY
            dragStartCenterY = frame.midY
            withAnimation(reorderAnimation) {
                hasActiveDragStarted = true
            }
        }
    }
    
    private func handleDragChanged(for block: DayBlock, at location: CGPoint) {
        if draggedBlockID == block.id {
            let centerY = location.y - dragGrabOffsetY
            dragCenterY = centerY
            let startCenterY = dragStartCenterY ?? centerY
            guard abs(centerY - startCenterY) > 4 else { return }
            updateVisualOrder(sourceID: block.id, centerY: centerY)
        }
    }
    
    private func handleDragEnded(for block: DayBlock) {
        guard draggedBlockID == block.id else { return }
        let didCommitMove = commitVisualOrder(sourceID: block.id)

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

    private func hairlineListConnector(from previous: DayBlock, to next: DayBlock) -> some View {
        let gap = next.startTime.timeIntervalSince(previous.endTime)
        let hasGap = gap > 60

        return VStack(alignment: .leading, spacing: 0) {
            if hasGap {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if scheduleDesign == .agenda {
                        Text(timeLabel(previous.endTime))
                            .font(CueInTypography.micro)
                            .monospacedDigit()
                            .foregroundStyle(CueInColors.textTertiary)
                            .frame(width: 50, alignment: .trailing)
                    }
                    Spacer()
                    Text(breakLabelIfNeeded(seconds: gap))
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.bottom, 2)
            }
            Rectangle()
                .fill(CueInColors.divider.opacity(0.4))
                .frame(height: 0.5)
        }
    }

    private func breakLabelIfNeeded(seconds: TimeInterval) -> String {
        let min = max(Int(seconds / 60), 1)
        if min >= 60 { return "Break \(min / 60)h" }
        return "Break \(min)m"
    }

    private func connector(from previous: DayBlock, to next: DayBlock) -> some View {
        let gap = next.startTime.timeIntervalSince(previous.endTime)
        let hasGap = gap > 60

        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                if hasGap {
                    Text(timeLabel(previous.endTime))
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                        .monospacedDigit()
                }
            }
            .frame(width: 38, alignment: .trailing)

            Rectangle()
                .fill(CueInColors.divider.opacity(0.75))
                .frame(width: 1, height: hasGap ? 24 : 14)
                .padding(.horizontal, CueInSpacing.md)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func timeLabel(_ date: Date) -> String {
        CueInTimeFormat.hourMinute(date)
    }

    private func hasCompleteFrameSet(_ frames: [UUID: CGRect]) -> Bool {
        guard !blocks.isEmpty else { return true }
        return blocks.allSatisfy { frames[$0.id] != nil }
    }

    private func baselineFramesForCurrentOrder() -> [UUID: CGRect] {
        if hasCompleteFrameSet(liveFrames),
           frameOrderMatchesCurrentBlocks(liveFrames) {
            return liveFrames
        }
        return synthesizedFrameSetForCurrentOrder(from: liveFrames)
    }

    private func frameOrderMatchesCurrentBlocks(_ frames: [UUID: CGRect]) -> Bool {
        guard hasCompleteFrameSet(frames) else { return false }
        let measuredOrder = blockIDs.sorted { lhs, rhs in
            guard let left = frames[lhs], let right = frames[rhs] else { return false }
            if abs(left.minY - right.minY) > 0.5 {
                return left.minY < right.minY
            }
            return left.minX < right.minX
        }
        return measuredOrder == blockIDs
    }

    private func synthesizedFrameSetForCurrentOrder(from sourceFrames: [UUID: CGRect]) -> [UUID: CGRect] {
        guard !blocks.isEmpty else { return [:] }

        let fallbackFrame = sourceFrames.values.first ?? CGRect(x: 0, y: 0, width: 1, height: 72)
        let startX = sourceFrames.values.map(\.minX).min() ?? fallbackFrame.minX
        let startY = sourceFrames.values.map(\.minY).min() ?? fallbackFrame.minY
        let fallbackWidth = max(fallbackFrame.width, 1)
        let fallbackHeight = max(fallbackFrame.height, 1)

        var cursorY = startY
        var synthesized: [UUID: CGRect] = [:]
        for block in blocks {
            let source = sourceFrames[block.id]
            let height = max(source?.height ?? fallbackHeight, 1)
            let width = max(source?.width ?? fallbackWidth, 1)
            synthesized[block.id] = CGRect(
                x: source?.minX ?? startX,
                y: cursorY,
                width: width,
                height: height
            )
            cursorY += height + blockStackSpacing
        }
        return synthesized
    }

    private func updateVisualOrder(sourceID: UUID, centerY: CGFloat) {
        let baselineOrder = blockIDs
        let nextOrder = ReorderEngine.visualOrder(
            orderedIDs: baselineOrder,
            baselineFrames: frozenFrames,
            draggedID: sourceID,
            centerY: centerY
        )

        guard nextOrder.count == baselineOrder.count,
              Set(nextOrder) == Set(baselineOrder),
              nextOrder != visualBlockIDs
        else { return }

        withAnimation(reorderAnimation) {
            visualBlockIDs = nextOrder
        }
        CueInHaptics.impact(.light)
    }

    private func commitVisualOrder(sourceID: UUID) -> Bool {
        guard visualBlockIDs.count == blockIDs.count,
              Set(visualBlockIDs) == Set(blockIDs),
              visualBlockIDs != blockIDs,
              let sourceIndex = visualBlockIDs.firstIndex(of: sourceID)
        else { return false }

        let nextIndex = sourceIndex + 1
        let targetID = visualBlockIDs.indices.contains(nextIndex) ? visualBlockIDs[nextIndex] : nil
        return onMoveBlock(sourceID, targetID)
    }

    private func clearDragState() {
        draggedBlockID = nil
        hasActiveDragStarted = false
        frozenFrames = [:]
        dragGrabOffsetY = 0
        dragCenterY = nil
        dragStartCenterY = nil
    }

    private func isDragOverlayReady(for blockID: UUID) -> Bool {
        frozenFrames[blockID] != nil && dragCenterY != nil && containerFrame != .zero
    }

    private func syncVisualOrder(force: Bool = false) {
        let ids = blockIDs
        guard force || visualBlockIDs.isEmpty || Set(visualBlockIDs) != Set(ids) else { return }
        visualBlockIDs = ids
    }

    /// Coalesce rapid per-row preference updates into one state write per runloop tick.
    /// This prevents layout feedback loops and reduces scheduler pressure while dragging.
    private func schedulePreferenceFrameFlushIfNeeded() {
        guard !hasScheduledPreferenceFlush else { return }
        hasScheduledPreferenceFlush = true
        DispatchQueue.main.async {
            hasScheduledPreferenceFlush = false
            let frames = pendingPreferenceFrames
            guard draggedBlockID == nil,
                  hasCompleteFrameSet(frames),
                  frameOrderMatchesCurrentBlocks(frames),
                  liveFrames != frames
            else { return }
            liveFrames = frames
        }
    }
}

// MARK: - Reorder engine (uses shared ReorderEngine)


// MARK: - UILongPressGestureRecognizer Wrapper

struct LongPressDragView: UIViewRepresentable {
    let onBegan: (CGPoint) -> Void
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void
    let onCancelled: () -> Void
    let onTapped: () -> Void
    var minimumPressDuration: TimeInterval = 0.18
    var allowableMovement: CGFloat = 18
    var recognizesSimultaneouslyWithScroll: Bool = false
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = minimumPressDuration
        longPress.allowableMovement = allowableMovement
        longPress.cancelsTouchesInView = true
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
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: LongPressDragView
        
        init(_ parent: LongPressDragView) {
            self.parent = parent
        }
        
        @objc func handleLongPress(_ sender: UILongPressGestureRecognizer) {
            let location = sender.location(in: nil) // global coordinates
            switch sender.state {
            case .began:
                parent.onBegan(location)
            case .changed:
                parent.onChanged(location)
            case .ended:
                parent.onEnded()
            case .cancelled, .failed:
                parent.onCancelled()
            case .possible:
                break
            @unknown default:
                break
            }
        }
        
        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            if sender.state == .ended {
                parent.onTapped()
            }
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            parent.recognizesSimultaneouslyWithScroll && isScrollViewGesture(otherGestureRecognizer)
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
