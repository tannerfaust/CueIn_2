import SwiftUI
import Observation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - ExecutionTimerHolder
/// Holds the clock `Timer` off the `@Observable` graph so `deinit` can invalidate safely
/// without `nonisolated(unsafe)` on stored properties (Swift 6 + Observation).
private final class ExecutionTimerHolder: @unchecked Sendable {
    /// `Timer` is touched from `TodayViewModel.deinit` (always nonisolated).
    nonisolated(unsafe) var timer: Timer?
}

private struct PersistedScheduleRunState: Codable {
    var selectedFormulaID: UUID?
    var blocks: [DayBlock]
    var formulaRunStartedAt: Date?
    var formulaStoppedAt: Date?
    /// Wall clock when the user paused a live run without stopping (blocks hold steady until resume).
    var formulaSchedulePausedAt: Date?
    var formulaTargetDayEnd: Date?
    var nominalMinutes: [PersistedScheduleNominalMinutes]
    var futurePinnedBlocks: [DayBlock]?
    var savedAt: Date
}

private struct PersistedScheduleNominalMinutes: Codable {
    var blockID: UUID
    var minutes: Int
}

// MARK: - TodayViewModel

@MainActor
@Observable
final class TodayViewModel {

    /// Shared instance so the Tasks tab can append to the same Today execution queue.
    @MainActor
    static let shared = TodayViewModel(
        dayRunPlanner: ProportionalWindowDayPlanner(),
        executionReflow: CascadeReflow(),
        availableFormulas: FormulaLibraryService.allSchedules
    )

    private static let persistedScheduleRunKey = "cuein.today.scheduleRun.v1"
    /// Persisted choice of which formula template drives Today (`nil` = user cleared; no key = default first template).
    private static let persistedFormulaSelectionKey = "cuein.today.formulaSelection.v1"
    private static let persistedFormulaSelectionClearedSentinel = "__cleared__"

    private static func loadPersistedFormulaSelection(availableFormulas: [DayFormulaTemplate]) -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: persistedFormulaSelectionKey) else {
            return availableFormulas.first?.id
        }
        if raw == persistedFormulaSelectionClearedSentinel { return nil }
        guard let id = UUID(uuidString: raw), availableFormulas.contains(where: { $0.id == id }) else {
            return availableFormulas.first?.id
        }
        return id
    }

    private static func persistFormulaSelection(_ id: UUID?) {
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: persistedFormulaSelectionKey)
        } else {
            UserDefaults.standard.set(persistedFormulaSelectionClearedSentinel, forKey: persistedFormulaSelectionKey)
        }
    }

    // MARK: State

    var blocks: [DayBlock]
    var currentTime: Date = Date()
    var dayEngineMode: DayEngineMode
    var taskLeadPresentation: TaskLeadPresentation = .tasksWithBlocks
    var classicDayScheduleStyle: ClassicDayScheduleStyle = .timedSlots
    private(set) var isExecutionPaused: Bool = false
    private(set) var executionPausedAt: Date? = nil

    private(set) var timelessRunStartedAt: Date?
    private(set) var timelessTargetDayEnd: Date?
    private var timelessNominalMinutesByBlockID: [UUID: Int] = [:]
    private(set) var selectedFormulaID: UUID?
    private(set) var availableFormulas: [DayFormulaTemplate]
    private(set) var formulaRunStartedAt: Date?
    private(set) var formulaStoppedAt: Date?
    /// Live formula run only: schedule block times / states use this instant instead of advancing with the wall clock.
    private(set) var formulaSchedulePausedAt: Date?
    private(set) var formulaTargetDayEnd: Date?
    private var formulaNominalMinutesByBlockID: [UUID: Int] = [:]
    private(set) var lastDayRunPlanMetadata: DayRunPlanMetadata?
    private(set) var executionDays: [ExecutionDayPlan] = []

    private var taskLeadBlocks: [DayBlock]
    private var formulaBlocks: [DayBlock] = []
    private var futurePinnedFormulaBlocks: [DayBlock] = []
    /// Bumps only on user-driven preview structure edits (blocks / tasks / pins). Reset when a template is (re)materialized or saved.
    private var formulaPreviewStructureEditGeneration: UInt = 0
    private var formulaPreviewStructureCleanGeneration: UInt = 0

    private let dayRunPlanner: DayRunPlanning
    private let executionReflow: ExecutionReflow
    /// Not part of observation; `deinit` invalidates the clock without actor hops.
    @ObservationIgnored private let executionTimer = ExecutionTimerHolder()
    /// Lifecycle observers keep schedule state tied to wall-clock time even if the app
    /// is suspended, resumed, or the system clock changes while we're inactive.
    @ObservationIgnored private var lifecycleObservers: [NSObjectProtocol] = []
    /// Skips redundant `UserDefaults` writes when the encoded schedule snapshot is unchanged (e.g. clock ticks).
    @ObservationIgnored private var lastPersistedScheduleData: Data?
    /// Throttles heavy ``deriveBlockStates`` while the formula clock ticks every second.
    @ObservationIgnored private var lastFormulaBlockDeriveAt: Date = .distantPast
    @ObservationIgnored private var executionTimerInterval: TimeInterval = 30

    // MARK: Init

    @MainActor
    init(
        dayRunPlanner: DayRunPlanning,
        executionReflow: ExecutionReflow,
        availableFormulas: [DayFormulaTemplate]
    ) {
        let now = Date()
        let restoredMode = Self.restoredDayEngineMode()
        let seededTaskLeadBlocks = MockDataService.sampleDay()

        self.dayRunPlanner = dayRunPlanner
        self.executionReflow = executionReflow
        self.availableFormulas = availableFormulas
        self.selectedFormulaID = Self.loadPersistedFormulaSelection(availableFormulas: availableFormulas)
        self.currentTime = now
        self.dayEngineMode = restoredMode
        self.taskLeadBlocks = seededTaskLeadBlocks
        self.blocks = restoredMode == .taskLed ? seededTaskLeadBlocks : []
        self.executionDays = Self.makeEmptyExecutionDays(relativeTo: now)
        syncExecutionPoolFromTasksStore()
        if restoredMode == .formulaBased {
            restoreFormulaRuntimeIfAvailable(now: now)
        }
        installLifecycleObservers()
    }

    /// Call after the universal `TaskDetailSheet` (or other Tasks-store editors) dismiss
    /// so execution cards reflect the latest `TaskItem` fields.
    @MainActor
    func syncExecutionTimelineAfterExternalTaskEdit() {
        syncExecutionPoolFromTasksStore()
    }

    @MainActor
    func onAppear() {
        currentTime = Date()
        syncExecutionPoolFromTasksStore()
        switch dayEngineMode {
        case .taskLed:
            loadTaskLeadDay(reset: taskLeadBlocks.isEmpty)
        case .formulaBased:
            if normalizeUnstartedStoppedFormulaRunIfNeeded() {
                break
            } else if selectedFormulaID == nil, !formulaBlocks.isEmpty {
                blocks = formulaBlocks
                deriveBlockStates()
            } else if selectedFormulaID == nil {
                blocks = []
                formulaBlocks = []
                deriveBlockStates()
            } else if formulaBlocks.isEmpty {
                prepareFormulaPreview()
            } else {
                blocks = formulaBlocks
                deriveBlockStates()
            }
        }

        startClock()
    }

    deinit {
        executionTimer.timer?.invalidate()
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        lifecycleObservers.removeAll()
    }

    // MARK: - Clock

    private var preferredExecutionTimerInterval: TimeInterval {
        guard dayEngineMode == .formulaBased else { return 30 }
        if isFormulaRunLive || isFormulaSchedulePaused { return 1 }
        return 30
    }

    private func startClock() {
        restartExecutionTimerIfNeeded()
    }

    /// Reschedules the timer when formula run / pause state changes the desired cadence.
    @MainActor
    private func restartExecutionTimerIfNeeded() {
        let interval = preferredExecutionTimerInterval
        guard abs(interval - executionTimerInterval) > 0.01
            || executionTimer.timer == nil
            || executionTimer.timer?.isValid != true
        else {
            return
        }
        executionTimerInterval = interval
        executionTimer.timer?.invalidate()
        executionTimer.timer = nil
        executionTimer.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickClock()
            }
        }
    }

    @MainActor
    private func tickClock() {
        currentTime = Date()

        if dayEngineMode == .formulaBased && isFormulaSchedulePaused {
            return
        }

        if dayEngineMode == .formulaBased && isFormulaRunLive {
            if currentTime.timeIntervalSince(lastFormulaBlockDeriveAt) < 30 {
                return
            }
            lastFormulaBlockDeriveAt = currentTime
        }

        deriveBlockStates()
    }

    @MainActor
    private func refreshClockFromSystem() {
        currentTime = Date()
        deriveBlockStates()
        if dayEngineMode == .formulaBased && isFormulaRunLive && !isFormulaSchedulePaused {
            lastFormulaBlockDeriveAt = currentTime
        }
        restartExecutionTimerIfNeeded()
    }

    private func installLifecycleObservers() {
        guard lifecycleObservers.isEmpty else { return }
        let center = NotificationCenter.default

        #if os(iOS)
        let foreground = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshClockFromSystem()
            }
        }

        let active = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshClockFromSystem()
            }
        }

        let significantTime = center.addObserver(
            forName: UIApplication.significantTimeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshClockFromSystem()
            }
        }

        let background = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = Date()
                self.deriveBlockStates()
            }
        }
        #elseif os(macOS)
        let foreground = center.addObserver(
            forName: NSApplication.willBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshClockFromSystem()
            }
        }

        let active = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshClockFromSystem()
            }
        }

        let significantTime = center.addObserver(
            forName: NSNotification.Name("NSSystemClockDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshClockFromSystem()
            }
        }

        let background = center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = Date()
                self.deriveBlockStates()
            }
        }
        #endif

        lifecycleObservers = [foreground, active, significantTime, background]
    }

    // MARK: - State Derivation

    func deriveBlockStates() {
        switch dayEngineMode {
        case .taskLed:
            switch classicDayScheduleStyle {
            case .timedSlots:
                deriveTimedSlotBlockStates()
            case .timeless:
                deriveTimelessBlockStates()
            }
        case .formulaBased:
            deriveFormulaBlockStates()
        }

        persistCurrentBlocks()
        restartExecutionTimerIfNeeded()
    }

    private func deriveTimedSlotBlockStates() {
        let now = currentTime
        for index in blocks.indices {
            if blocks[index].state == .skipped || blocks[index].state == .completed { continue }
            if now >= blocks[index].endTime {
                blocks[index].state = .completed
            } else if now >= blocks[index].startTime && now < blocks[index].endTime {
                blocks[index].state = .active
            } else {
                blocks[index].state = .upcoming
            }
        }
    }

    private func deriveTimelessBlockStates() {
        deriveProgressiveRunBlockStates(runStartedAt: timelessRunStartedAt, progressNow: nil)
    }

    private func deriveFormulaBlockStates() {
        guard formulaStoppedAt == nil else { return }
        if formulaSchedulePausedAt == nil {
            recalibrateOverdueBlockingFormulaRun()
        }
        let progressNow = formulaSchedulePausedAt ?? currentTime
        deriveProgressiveRunBlockStates(runStartedAt: formulaRunStartedAt, progressNow: progressNow)
        if formulaSchedulePausedAt == nil {
            ensureLiveFormulaRunHasActiveBlock()
        }
        if isFormulaRunLive {
            injectScheduleBlocksIntoTimeline()
        }
    }

    private func ensureLiveFormulaRunHasActiveBlock() {
        guard formulaSchedulePausedAt == nil else { return }
        guard isFormulaRunLive, currentBlock == nil, remainingBlockCount > 0 else { return }
        guard let activeIndex = blocks.firstIndex(where: {
            $0.state != .completed && $0.state != .skipped
        }) else { return }

        let now = currentTime
        for index in blocks.indices {
            if blocks[index].state == .completed || blocks[index].state == .skipped { continue }
            blocks[index].state = index == activeIndex ? .active : .upcoming
        }

        guard !isFixedTimeScheduleBlock(blocks[activeIndex]) else { return }

        let activeMinutes = formulaNominalMinutesByBlockID[blocks[activeIndex].id]
            ?? max(blocks[activeIndex].durationMinutes, 1)
        blocks[activeIndex].startTime = now
        blocks[activeIndex].endTime = calendar.date(
            byAdding: .minute,
            value: max(activeMinutes, 1),
            to: now
        ) ?? now

        let tail = blocks.indices.filter { index in
            index > activeIndex
                && blocks[index].state != .completed
                && blocks[index].state != .skipped
        }
        if !tail.isEmpty {
            reflowFormulaBlocksAroundFixedTimes(
                plannedBlockIndices: Array(tail),
                runStart: blocks[activeIndex].endTime,
                targetEnd: effectiveFormulaTargetEnd(from: now)
            )
        }
    }

    private var hasMeaningfulStoppedFormulaRun: Bool {
        guard let stoppedAt = formulaStoppedAt else { return false }
        guard let firstStart = blocks.map(\.startTime).min() else { return false }

        if blocks.contains(where: { $0.state == .completed }) {
            return true
        }

        // A stopped schedule with no completed work and only a few seconds of elapsed time
        // is visually and behaviorally still a preview. Treat stale zero-progress runtime
        // snapshots that way so Today shows Start instead of paused controls.
        return stoppedAt.timeIntervalSince(firstStart) >= 30
    }

    private func deriveProgressiveRunBlockStates(runStartedAt: Date?, progressNow: Date?) {
        guard runStartedAt != nil else {
            for index in blocks.indices {
                if blocks[index].state == .skipped { continue }
                blocks[index].state = .upcoming
            }
            return
        }

        let now = progressNow ?? currentTime
        for index in blocks.indices {
            if blocks[index].state == .skipped { continue }

            let priorsDone = (0..<index).allSatisfy { priorIndex in
                blocks[priorIndex].state == .completed || blocks[priorIndex].state == .skipped
            }
            if !priorsDone {
                blocks[index].state = .upcoming
                continue
            }

            if blocks[index].state == .completed { continue }

            let start = blocks[index].startTime
            let end = blocks[index].endTime

            switch blocks[index].flowMode {
            case .flowing:
                if now >= end {
                    blocks[index].state = .completed
                } else if now >= start {
                    blocks[index].state = .active
                } else {
                    blocks[index].state = .upcoming
                }
            case .blocking:
                blocks[index].state = now < start ? .upcoming : .active
            }
        }
    }

    // MARK: - Computed

    var currentBlock: DayBlock? { blocks.first { $0.state == .active } }
    var currentBlockID: UUID? { currentBlock?.id }
    var todayScheduleBlocks: [DayBlock] {
        todayEligibleScheduleBlocks(from: blocks)
    }
    var futurePinnedScheduleBlocks: [DayBlock] {
        let todayStart = calendar.startOfDay(for: currentTime)
        let combined = futurePinnedFormulaBlocks + blocks
        var seen = Set<UUID>()
        return combined
            .filter { block in
                guard block.pinsToClock || block.isAnchorBlock else { return false }
                return calendar.startOfDay(for: block.startTime) > todayStart
            }
            .filter { block in
                if seen.contains(block.id) { return false }
                seen.insert(block.id)
                return true
            }
            .sorted { $0.startTime < $1.startTime }
    }
    var completedBlockCount: Int { blocks.filter { $0.state == .completed }.count }
    var remainingBlockCount: Int { blocks.filter { $0.state == .upcoming || $0.state == .active }.count }
    var totalTaskCount: Int { blocks.flatMap(\.tasks).count }
    var completedTaskCount: Int { blocks.flatMap(\.tasks).filter(\.isCompleted).count }
    var openTaskCount: Int { totalTaskCount - completedTaskCount }
    var priorityTaskCount: Int { blocks.flatMap(\.tasks).filter { $0.isPrimary && !$0.isCompleted }.count }
    var isFormulaMode: Bool { dayEngineMode == .formulaBased }
    var isTaskLedMode: Bool { dayEngineMode == .taskLed }

    var selectedFormula: DayFormulaTemplate? {
        guard let selectedFormulaID else { return nil }
        return availableFormulas.first(where: { $0.id == selectedFormulaID })
    }

    /// `true` when Schedule has content that can be started, from a saved template or manual blocks.
    var hasFormulaTemplate: Bool { selectedFormulaID != nil || !todayScheduleBlocks.isEmpty }

    /// Today is in Schedule mode with no template and no live run — show the empty-state callout.
    var shouldShowScheduleEmptyCallout: Bool {
        isFormulaMode && selectedFormulaID == nil && todayScheduleBlocks.isEmpty && !isFormulaRunLive
    }

    /// Whether “Clear the schedule” can do meaningful work.
    var canClearFormulaSchedule: Bool {
        guard isFormulaMode else { return false }
        return isFormulaRunLive || isFormulaRunStopped || selectedFormulaID != nil || !blocks.isEmpty
    }

    var isTimelessRunLive: Bool {
        dayEngineMode == .taskLed
            && classicDayScheduleStyle == .timeless
            && timelessRunStartedAt != nil
    }

    var isFormulaRunLive: Bool {
        dayEngineMode == .formulaBased && formulaRunStartedAt != nil
    }

    var isFormulaRunStopped: Bool {
        dayEngineMode == .formulaBased && hasMeaningfulStoppedFormulaRun
    }

    var hasFormulaRunStarted: Bool {
        isFormulaRunLive || isFormulaRunStopped
    }

    var isFormulaPreviewing: Bool {
        dayEngineMode == .formulaBased && formulaRunStartedAt == nil && !isFormulaRunStopped
    }

    /// Short label for the navigation bar in Schedule mode: saved template name, or a neutral draft label when there are blocks but no library selection.
    var formulaScheduleNavigationTitle: String {
        guard isFormulaMode else { return "" }
        if let name = selectedFormula?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if !todayScheduleBlocks.isEmpty {
            return "Draft schedule"
        }
        return "Blocks"
    }

    /// `true` when the selected template is one of the user's saved library schedules (not a bundled sample).
    var isSelectedFormulaUserSavedSchedule: Bool {
        guard let id = selectedFormulaID else { return false }
        return FormulaLibraryService.customSchedules().contains(where: { $0.id == id })
    }

    /// Seed values for ``FormulaScheduleSaveSheet`` when there is no selected template (e.g. after Clear schedule, then building from blocks).
    var formulaScheduleSaveSheetSeed: (name: String, symbol: String, summary: String) {
        if let formula = selectedFormula {
            return (formula.name, formula.symbol, formula.summary)
        }
        let name = FormulaLibraryService.uniquedScheduleDisplayName(
            startingWith: "My schedule",
            excludingScheduleID: nil
        )
        return (name, "calendar", "")
    }

    /// `true` only after the user changes preview blocks (add / remove / reorder / edit / unpin, etc.). Resets when the template is loaded or successfully saved.
    var isFormulaPreviewScheduleDirty: Bool {
        guard isFormulaPreviewing else { return false }
        guard !scheduleBlocksForLibraryTemplateRoundTrip().isEmpty else { return false }
        return formulaPreviewStructureEditGeneration != formulaPreviewStructureCleanGeneration
    }

    var isFormulaSchedulePaused: Bool { formulaSchedulePausedAt != nil }

    /// Extends the planned day end with elapsed pause time so running-line progress stays continuous across resume.
    private func effectiveFormulaDayTargetEnd(for referenceNow: Date) -> Date? {
        guard dayEngineMode == .formulaBased else { return nil }
        guard let base = formulaTargetDayEnd ?? blocks.last?.endTime else { return nil }
        if let pausedAt = formulaSchedulePausedAt {
            return base.addingTimeInterval(referenceNow.timeIntervalSince(pausedAt))
        }
        return base
    }

    private func formatRemainingDuration(seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 0.5 { return "Done" }
        let total = Int(floor(s + 0.0001))
        if total <= 0 { return "Done" }
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        if h > 0 {
            if m > 0 && sec > 0 { return "\(h)h \(m)m \(sec)s left" }
            if m > 0 { return "\(h)h \(m)m left" }
            if sec > 0 { return "\(h)h \(sec)s left" }
            return "\(h)h left"
        }
        if m > 0 {
            if sec > 0 { return "\(m)m \(sec)s left" }
            return "\(m)m left"
        }
        return "\(sec)s left"
    }

    var runningLineTitle: String? {
        if isTaskLedMode {
            return currentExecutionTask?.title
                ?? todayExecutionDay?.tasks.first(where: { !$0.isCompleted })?.title
        }

        if let currentBlock {
            return currentBlock.title
        }

        if isFormulaPreviewing {
            return selectedFormula?.name
        }

        return nil
    }

    var runningLineRemainingLabel: String {
        let targetEnd: Date?
        switch dayEngineMode {
        case .taskLed:
            targetEnd = timelessTargetDayEnd ?? blocks.last?.endTime
        case .formulaBased:
            targetEnd = formulaTargetDayEnd ?? blocks.last?.endTime
        }

        guard let targetEnd else { return "No end set" }
        let referenceTime: Date
        if dayEngineMode == .formulaBased {
            if isFormulaSchedulePaused {
                referenceTime = currentTime
            } else {
                referenceTime = formulaStoppedAt ?? currentTime
            }
        } else {
            referenceTime = currentTime
        }

        let endForRemaining: Date
        if let extended = effectiveFormulaDayTargetEnd(for: currentTime) {
            endForRemaining = extended
        } else {
            endForRemaining = targetEnd
        }

        let remainingSeconds = max(0, endForRemaining.timeIntervalSince(referenceTime))
        return formatRemainingDuration(seconds: remainingSeconds)
    }

    var runningLineAccentColors: [Color] {
        let source = todayScheduleBlocks.isEmpty ? blocks : todayScheduleBlocks
        var colors: [Color] = []
        var seen: Set<String> = []
        for block in source {
            let key: String
            let color: Color
            if let hex = block.timelineAccentHex {
                key = "hex-\(hex)"
                color = CueInColors.color(hexUInt32: hex)
            } else {
                key = "type-\(block.type.rawValue)"
                color = block.type.accent
            }
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            colors.append(color)
        }
        return colors
    }

    /// Running-line fill: follow the **current** block’s accent through the day instead of a multi-color strip.
    var runningLineProgressAccentPalette: [Color] {
        guard dayEngineMode == .formulaBased, hasFormulaRunStarted else {
            return runningLineAccentColors
        }
        let primary = runningLineCurrentProgressAccent
        return [primary]
    }

    /// Accent for the filled portion of the schedule running line (active block, else next upcoming slice).
    private var runningLineCurrentProgressAccent: Color {
        if let b = currentBlock {
            return CueInColors.resolvedTimelineAccent(blockType: b.type, hex: b.timelineAccentHex)
        }
        if let next = blocks.first(where: { $0.state == .upcoming }) {
            return CueInColors.resolvedTimelineAccent(blockType: next.type, hex: next.timelineAccentHex)
        }
        if let last = blocks.last {
            return CueInColors.resolvedTimelineAccent(blockType: last.type, hex: last.timelineAccentHex)
        }
        return runningLineAccentColors.first ?? CueInColors.accentFocus
    }

    /// Schedule running line: each block’s share of the formula timeline, for segmented fills.
    var runningLineBlockSegments: [RunningLineBlockSegment] {
        guard dayEngineMode == .formulaBased, hasFormulaRunStarted,
              let (progressStart, progressEndDate) = formulaRunningLineTimelineBounds() else { return [] }
        let total = progressEndDate.timeIntervalSince(progressStart)
        guard total > 0 else { return [] }
        return blocks
            .sorted { $0.startTime < $1.startTime }
            .compactMap { block -> RunningLineBlockSegment? in
                let dur = max(0, block.endTime.timeIntervalSince(block.startTime))
                guard dur > 0 else { return nil }
                let fraction = CGFloat(dur / total)
                let color = CueInColors.resolvedTimelineAccent(blockType: block.type, hex: block.timelineAccentHex)
                return RunningLineBlockSegment(fraction: fraction, color: color)
            }
    }

    /// Wall-clock anchor for formula running-line math: freezes at pause in “End later” so progress doesn’t creep.
    private var formulaRunningLineProgressAnchor: Date {
        if isFormulaSchedulePaused, let p = formulaSchedulePausedAt { return p }
        return formulaStoppedAt ?? currentTime
    }

    private func formulaRunningLineTimelineBounds() -> (start: Date, end: Date)? {
        guard dayEngineMode == .formulaBased, hasFormulaRunStarted,
              let first = blocks.first, let last = blocks.last else { return nil }
        let progressStart = formulaRunStartedAt ?? first.startTime
        let anchor = formulaRunningLineProgressAnchor
        let progressEnd = effectiveFormulaDayTargetEnd(for: anchor) ?? (formulaTargetDayEnd ?? last.endTime)
        return (progressStart, progressEnd)
    }

    var headerStatusLine: String {
        if isTaskLedMode {
            let day = todayExecutionDay
            return "\(day?.openTaskCount ?? openTaskCount) open · \(day?.priorityTaskCount ?? priorityTaskCount) priority"
        }

        if isFormulaPreviewing {
            return ""
        }

        if isFormulaSchedulePaused {
            return "Paused · \(remainingBlockCount) blocks · \(completedTaskCount)/\(totalTaskCount) tasks"
        }

        if isFormulaRunStopped {
            return "Stopped · \(completedTaskCount)/\(totalTaskCount) tasks"
        }

        return "\(remainingBlockCount) blocks · \(completedTaskCount)/\(totalTaskCount) tasks"
    }

    /// Task-led execution: stats for the calendar day currently in view (scroll-synced header).
    func executionHeaderStatusLine(forDayStartingAt dayStart: Date) -> String {
        guard let day = executionDays.first(where: { calendar.isDate($0.date, inSameDayAs: dayStart) }) else {
            return "\(openTaskCount) open · \(priorityTaskCount) priority"
        }
        return "\(day.openTaskCount) open · \(day.priorityTaskCount) priority"
    }

    var currentExecutionTask: ExecutionTaskCard? {
        guard let todayExecutionDay else { return nil }
        return todayExecutionDay.tasks
            .filter { !$0.isCompleted && currentTime >= $0.startDate && currentTime < $0.endDate }
            .sorted { $0.startDate < $1.startDate }
            .first
    }

    var unresolvedExecutionTask: ExecutionTaskCard? {
        guard let todayExecutionDay else { return nil }
        return todayExecutionDay.tasks
            .filter { !$0.isCompleted && $0.endDate <= currentTime }
            .sorted {
                if $0.endDate != $1.endDate { return $0.endDate < $1.endDate }
                return $0.startDate < $1.startDate
            }
            .first
    }

    /// The first uncompleted task that starts at or after `currentTime` (and isn’t the current one).
    var nextExecutionTask: ExecutionTaskCard? {
        guard let todayExecutionDay else { return nil }
        let skipID = currentExecutionTask?.id
        let unresolvedID = unresolvedExecutionTask?.id
        return todayExecutionDay.tasks
            .filter { !$0.isCompleted && $0.startDate > currentTime && $0.id != skipID && $0.id != unresolvedID }
            .sorted { $0.startDate < $1.startDate }
            .first
    }

    var scheduleMakerTaskScopes: ScheduleMakerTaskScopes {
        let tasks = todayExecutionDay?.tasks ?? executionDays.first?.tasks ?? []
        return ScheduleMakerTaskScopes(tasks: tasks)
    }

    var scheduleStartPreview: ScheduleStartPreview {
        makeScheduleStartPreview(targetEnd: nil, runStart: Date())
    }

    func scheduleStartPreview(targetEnd: Date) -> ScheduleStartPreview {
        makeScheduleStartPreview(targetEnd: targetEnd, runStart: Date())
    }

    private func makeScheduleStartPreview(targetEnd requestedTargetEnd: Date?, runStart: Date) -> ScheduleStartPreview {
        let previewBlocks = scheduleStartSourceBlocks(runStart: runStart)
        let pinnedPreviewBlocks = blocksPinnedToRunDate(previewBlocks, runStart: runStart)
        let openTasks = (todayExecutionDay?.tasks ?? []).filter { !$0.isCompleted }
        let nominalMinutes = selectedFormula?.totalNominalMinutes ?? pinnedPreviewBlocks.reduce(0) { $0 + max($1.durationMinutes, 1) }
        let targetEnd = requestedTargetEnd ?? defaultScheduleTargetEnd(for: pinnedPreviewBlocks, runStart: runStart, nominalMinutes: nominalMinutes)
        let preflight = makeScheduleStartPreflight(
            blocks: pinnedPreviewBlocks,
            runStart: runStart,
            targetEnd: targetEnd
        )

        return ScheduleStartPreview(
            blockCount: pinnedPreviewBlocks.count,
            routineBlockCount: pinnedPreviewBlocks.filter { $0.taskSource == .templateTasks }.count,
            fillBlockCount: pinnedPreviewBlocks.filter { $0.taskSource == .executionFill }.count,
            noTasksBlockCount: pinnedPreviewBlocks.filter { $0.taskSource == .noTasks }.count,
            pinnedBlockCount: pinnedPreviewBlocks.filter { $0.pinsToClock || $0.isAnchorBlock }.count,
            openExecutionTaskCount: openTasks.count,
            priorityTaskCount: openTasks.filter(\.isPrimary).count,
            nominalMinutes: nominalMinutes,
            preflightIssues: preflight.issues,
            recommendedMinimumEnd: preflight.recommendedMinimumEnd
        )
    }

    var defaultScheduleTargetEnd: Date {
        let runStart = Date()
        let previewBlocks = scheduleStartSourceBlocks(runStart: runStart)
        let pinnedPreviewBlocks = blocksPinnedToRunDate(previewBlocks, runStart: runStart)
        let nominalMinutes = selectedFormula?.totalNominalMinutes ?? pinnedPreviewBlocks.reduce(0) { $0 + max($1.durationMinutes, 1) }
        return defaultScheduleTargetEnd(for: pinnedPreviewBlocks, runStart: runStart, nominalMinutes: nominalMinutes)
    }

    private func scheduleStartSourceBlocks(runStart: Date) -> [DayBlock] {
        if blocks.isEmpty {
            return todayEligibleScheduleBlocks(from: selectedFormula?.materializeDay(startingAt: runStart) ?? [], relativeTo: runStart)
        }
        return todayEligibleScheduleBlocks(from: blocks, relativeTo: runStart)
    }

    private func todayEligibleScheduleBlocks(from sourceBlocks: [DayBlock], relativeTo date: Date? = nil) -> [DayBlock] {
        let targetDay = calendar.startOfDay(for: date ?? currentTime)
        return sourceBlocks.filter { block in
            guard block.pinsToClock || block.isAnchorBlock else { return true }
            return calendar.isDate(block.startTime, inSameDayAs: targetDay)
        }
    }

    private func futurePinnedScheduleBlocks(from sourceBlocks: [DayBlock], relativeTo date: Date? = nil) -> [DayBlock] {
        let targetDay = calendar.startOfDay(for: date ?? currentTime)
        return sourceBlocks.filter { block in
            guard block.pinsToClock || block.isAnchorBlock else { return false }
            return calendar.startOfDay(for: block.startTime) > targetDay
        }
    }

    private func stashFuturePinnedFormulaBlocks(_ sourceBlocks: [DayBlock], relativeTo date: Date? = nil) {
        let future = futurePinnedScheduleBlocks(from: sourceBlocks, relativeTo: date)
        guard !future.isEmpty else { return }

        var byID = Dictionary(uniqueKeysWithValues: futurePinnedFormulaBlocks.map { ($0.id, $0) })
        for block in future {
            byID[block.id] = block
        }
        futurePinnedFormulaBlocks = byID.values.sorted { $0.startTime < $1.startTime }
    }

    private func defaultScheduleTargetEnd(
        for previewBlocks: [DayBlock],
        runStart: Date,
        nominalMinutes: Int
    ) -> Date {
        let chronological = previewBlocks.sorted { $0.startTime < $1.startTime }
        let nominalFallbackMinutes = max(
            selectedFormula?.targetDurationMinutes ?? 0,
            selectedFormula?.totalNominalMinutes ?? nominalMinutes,
            previewBlocks.reduce(0) { $0 + max($1.durationMinutes, 1) },
            60
        )
        let nominalFloorSeconds = TimeInterval(nominalFallbackMinutes * 60)

        let spanSeconds: TimeInterval
        if let first = chronological.first,
           let last = chronological.last,
           last.endTime > first.startTime {
            spanSeconds = last.endTime.timeIntervalSince(first.startTime)
        } else {
            spanSeconds = nominalFloorSeconds
        }

        let effectiveSpan = max(spanSeconds, nominalFloorSeconds, 60)
        return runStart.addingTimeInterval(effectiveSpan)
    }

    private func blocksPinnedToRunDate(_ sourceBlocks: [DayBlock], runStart: Date) -> [DayBlock] {
        sourceBlocks.map { block in
            var adjusted = block
            guard adjusted.pinsToClock,
                  let pinnedStart = pinnedClockStart(for: adjusted, runStart: runStart)
            else { return adjusted }

            let durationMinutes = max(adjusted.durationMinutes, 1)
            adjusted.startTime = pinnedStart
            adjusted.endTime = calendar.date(byAdding: .minute, value: durationMinutes, to: pinnedStart)
                ?? pinnedStart.addingTimeInterval(TimeInterval(durationMinutes * 60))
            return adjusted
        }
    }

    private func pinnedClockStart(for block: DayBlock, runStart: Date) -> Date? {
        guard block.pinsToClock else { return nil }
        let dayStart = calendar.startOfDay(for: block.startTime)
        let components = calendar.dateComponents([.hour, .minute], from: block.startTime)
        let minutes = max(0, min((components.hour ?? 0) * 60 + (components.minute ?? 0), (24 * 60) - 1))
        return calendar.date(byAdding: .minute, value: minutes, to: dayStart)
    }

    private func makeScheduleStartPreflight(
        blocks previewBlocks: [DayBlock],
        runStart: Date,
        targetEnd: Date
    ) -> (issues: [ScheduleStartPreflightIssue], recommendedMinimumEnd: Date?) {
        guard !previewBlocks.isEmpty else { return ([], nil) }

        var issues: [ScheduleStartPreflightIssue] = []
        var cursor = runStart
        var flexibleSegment: [DayBlock] = []
        var recommendedMinimumEnd = targetEnd

        func minutesBetween(_ start: Date, _ end: Date) -> Int {
            max(0, Int(ceil(end.timeIntervalSince(start) / 60.0)))
        }

        func nominalMinutes(_ segment: [DayBlock]) -> Int {
            segment.reduce(0) { $0 + max($1.durationMinutes, 1) }
        }

        func minimumMinutes(_ segment: [DayBlock]) -> Int {
            segment.reduce(0) { total, block in
                let nominal = max(block.durationMinutes, 1)
                if block.locksPlannedDuration {
                    return total + nominal
                }
                return total + max(1, min(TodayDisplayPreferences.minimumFlexibleBlockMinutesPreference(), nominal))
            }
        }

        func inspectFlexibleSegment(endingAt segmentEnd: Date, boundaryTitle: String, boundaryID: UUID?) {
            let window = minutesBetween(cursor, segmentEnd)
            let nominal = nominalMinutes(flexibleSegment)
            let minimum = minimumMinutes(flexibleSegment)
            let boundaryActions = pinnedBlockActions(blockID: boundaryID)

            guard !flexibleSegment.isEmpty else {
                if window >= 45 {
                    issues.append(
                        ScheduleStartPreflightIssue(
                            id: "gap-\(boundaryID?.uuidString ?? "end")-\(Int(cursor.timeIntervalSince1970))",
                            severity: .warning,
                            title: "Open gap before \(boundaryTitle)",
                            message: "\(window)m is empty before the pinned time.",
                            suggestion: "Fill it with another block, move flexible work into the gap, or accept the idle window.",
                            actions: boundaryActions
                        )
                    )
                }
                return
            }

            if window < minimum {
                recommendedMinimumEnd = max(
                    recommendedMinimumEnd,
                    calendar.date(byAdding: .minute, value: minimum - window, to: targetEnd) ?? targetEnd
                )
                issues.append(
                    ScheduleStartPreflightIssue(
                        id: "tight-\(boundaryID?.uuidString ?? "end")",
                        severity: .critical,
                        title: "Not enough room before \(boundaryTitle)",
                        message: "\(flexibleSegment.count) flexible block\(flexibleSegment.count == 1 ? "" : "s") need at least \(minimum)m, but the pinned window has \(window)m.",
                        suggestion: boundaryID == nil
                            ? "Use the safe end or shorten locked durations."
                            : "Unpin or delete the pinned block, or move earlier work around it.",
                        actions: boundaryID == nil ? [.useSafeEnd] : boundaryActions
                    )
                )
            } else if nominal > 0, Double(window) < Double(nominal) * 0.65 {
                issues.append(
                    ScheduleStartPreflightIssue(
                        id: "compress-\(boundaryID?.uuidString ?? "end")",
                        severity: .warning,
                        title: "Blocks will compress before \(boundaryTitle)",
                        message: "\(nominal)m of planned work will fit into \(window)m.",
                        suggestion: "Higher-priority blocks keep more room; lower-priority blocks shrink first.",
                        actions: boundaryActions
                    )
                )
            } else if window > nominal + 60 {
                issues.append(
                    ScheduleStartPreflightIssue(
                        id: "stretch-\(boundaryID?.uuidString ?? "end")",
                        severity: .notice,
                        title: "Blocks will stretch before \(boundaryTitle)",
                        message: "\(nominal)m of planned work has \(window)m available.",
                        suggestion: "Add another block, fill from Execution, or let the engine expand the segment.",
                        actions: boundaryActions
                    )
                )
            }
        }

        for block in previewBlocks {
            if isFixedTimeScheduleBlock(block) {
                if block.endTime <= runStart {
                    issues.append(
                        ScheduleStartPreflightIssue(
                            id: "past-\(block.id.uuidString)",
                            severity: .critical,
                            title: "\(block.title) has already passed",
                            message: "It is pinned at \(CueInTimeFormat.hourMinute(block.startTime)), before this run can start.",
                            suggestion: "Unpin it to let the schedule place it, or delete it from today’s run.",
                            actions: pinnedBlockActions(blockID: block.id)
                        )
                    )
                } else if block.startTime < cursor {
                    issues.append(
                        ScheduleStartPreflightIssue(
                            id: "overlap-\(block.id.uuidString)",
                            severity: .critical,
                            title: "\(block.title) overlaps the running plan",
                            message: "The pinned start is \(CueInTimeFormat.hourMinute(block.startTime)), but previous work reaches \(CueInTimeFormat.hourMinute(cursor)).",
                            suggestion: "Unpin it to reflow, or delete it if it should not be part of this run.",
                            actions: pinnedBlockActions(blockID: block.id)
                        )
                    )
                } else {
                    inspectFlexibleSegment(endingAt: block.startTime, boundaryTitle: block.title, boundaryID: block.id)
                }

                flexibleSegment.removeAll(keepingCapacity: true)
                if block.endTime > cursor {
                    cursor = block.endTime
                }
            } else {
                flexibleSegment.append(block)
            }
        }

        if targetEnd <= cursor {
            issues.append(
                ScheduleStartPreflightIssue(
                    id: "target-before-tail",
                    severity: .critical,
                    title: "End time is before the pinned plan clears",
                    message: "Pinned blocks already reach \(CueInTimeFormat.hourMinute(cursor)), after the selected end.",
                    suggestion: "Use the safe end or unpin the pinned block that pushes the plan past the target.",
                    actions: [.useSafeEnd]
                )
            )
            recommendedMinimumEnd = max(recommendedMinimumEnd, cursor.addingTimeInterval(60))
        } else {
            inspectFlexibleSegment(endingAt: targetEnd, boundaryTitle: "the end", boundaryID: nil)
        }

        return (issues, recommendedMinimumEnd > targetEnd ? recommendedMinimumEnd : nil)
    }

    private func pinnedBlockActions(blockID: UUID?) -> [ScheduleStartPreflightAction] {
        guard let blockID else { return [] }
        if blocks.first(where: { $0.id == blockID })?.isAnchorBlock == true {
            return [.deleteBlock(blockID)]
        }
        return [.unpinBlock(blockID), .deleteBlock(blockID)]
    }

    /// 0…1 — how far through the currently running task we are (stable when no current task).
    var currentExecutionProgress: Double {
        guard let task = currentExecutionTask else { return 0 }
        let total = task.endDate.timeIntervalSince(task.startDate)
        guard total > 0 else { return 0 }
        let elapsed = currentTime.timeIntervalSince(task.startDate)
        return min(max(elapsed / total, 0), 1)
    }

    private var todayExecutionDay: ExecutionDayPlan? {
        executionDays.first(where: { calendar.isDate($0.date, inSameDayAs: currentTime) })
    }

    /// Used by stats when the execution snapshot is already hydrated for today.
    var todayExecutionDayTaskCountForMetrics: Int? {
        todayExecutionDay.map { $0.tasks.count }
    }

    var taskLeadSections: [TaskLeadTaskSection] {
        guard isTaskLedMode else { return [] }

        let items = flatTaskLeadItems
        var usedTaskIDs = Set<UUID>()
        var sections: [TaskLeadTaskSection] = []

        let currentItems = items.filter { !$0.isCompleted && $0.blockState == .active }
        appendTaskLeadSection(
            id: "current",
            title: "Current",
            subtitle: currentBlock?.title,
            items: currentItems,
            usedTaskIDs: &usedTaskIDs,
            into: &sections
        )

        let priorityItems = items.filter { item in
            !item.isCompleted && item.task.isPrimary && !usedTaskIDs.contains(item.id)
        }
        appendTaskLeadSection(
            id: "priority",
            title: "Priority",
            subtitle: nil,
            items: priorityItems,
            usedTaskIDs: &usedTaskIDs,
            into: &sections
        )

        let openItems = items.filter { item in
            !item.isCompleted && !usedTaskIDs.contains(item.id)
        }
        appendTaskLeadSection(
            id: "open",
            title: "Open",
            subtitle: nil,
            items: openItems,
            usedTaskIDs: &usedTaskIDs,
            into: &sections
        )

        let completedItems = items.filter(\.isCompleted)
        appendTaskLeadSection(
            id: "done",
            title: "Done",
            subtitle: nil,
            items: completedItems,
            usedTaskIDs: &usedTaskIDs,
            into: &sections
        )

        return sections
    }

    var dayProgress: Double {
        guard let first = blocks.first, let last = blocks.last else { return 0 }

        let progressStart: TimeInterval
        let progressEndDate: Date
        let progressNow: Date

        switch dayEngineMode {
        case .taskLed:
            if classicDayScheduleStyle == .timeless && timelessRunStartedAt == nil { return 0 }
            progressStart = first.startTime.timeIntervalSince1970
            progressEndDate = timelessTargetDayEnd ?? last.endTime
            progressNow = currentTime
        case .formulaBased:
            if !hasFormulaRunStarted { return 0 }
            guard let (startDate, endDate) = formulaRunningLineTimelineBounds() else { return 0 }
            progressStart = startDate.timeIntervalSince1970
            progressEndDate = endDate
            progressNow = formulaRunningLineProgressAnchor
        }

        let end = progressEndDate.timeIntervalSince1970
        let now = progressNow.timeIntervalSince1970
        guard end > progressStart else { return 0 }
        return min(max((now - progressStart) / (end - progressStart), 0), 1)
    }

    // MARK: - Actions

    @MainActor
    func setDayEngineMode(_ mode: DayEngineMode) {
        guard dayEngineMode != mode else { return }

        persistCurrentBlocks()
        dayEngineMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: DayEngineMode.storageKey)

        switch mode {
        case .taskLed:
            loadTaskLeadDay(reset: taskLeadBlocks.isEmpty)
        case .formulaBased:
            if selectedFormulaID == nil, !formulaBlocks.isEmpty {
                blocks = formulaBlocks
                deriveBlockStates()
            } else if selectedFormulaID == nil {
                blocks = []
                formulaBlocks = []
                deriveBlockStates()
            } else if formulaBlocks.isEmpty {
                prepareFormulaPreview()
            } else {
                blocks = formulaBlocks
                deriveBlockStates()
            }
        }
    }

    @MainActor
    func setTaskLeadPresentation(_ presentation: TaskLeadPresentation) {
        taskLeadPresentation = presentation
    }

    @MainActor
    func setClassicDayScheduleStyle(_ style: ClassicDayScheduleStyle) {
        if dayEngineMode != .taskLed {
            setDayEngineMode(.taskLed)
        }

        if style == .timedSlots && classicDayScheduleStyle != .timedSlots {
            clearTimelessRuntime()
            loadTaskLeadDay(reset: true)
            classicDayScheduleStyle = .timedSlots
            deriveBlockStates()
            return
        }

        classicDayScheduleStyle = style
        if taskLeadBlocks.isEmpty {
            loadTaskLeadDay(reset: true)
        } else {
            blocks = taskLeadBlocks
            deriveBlockStates()
        }
    }

    @MainActor
    func startTimelessRun(dayEnd: Date) {
        guard dayEngineMode == .taskLed, classicDayScheduleStyle == .timeless else { return }
        let now = Date()
        currentTime = now
        guard dayEnd > now else { return }

        snapshotTimelessNominals()
        timelessTargetDayEnd = dayEnd
        timelessRunStartedAt = now

        for index in blocks.indices {
            if blocks[index].state == .skipped { continue }
            blocks[index].state = .upcoming
        }

        let planned = blocks.indices.filter { blocks[$0].state != .skipped }
        guard !planned.isEmpty else { return }

        applyTimelessPlan(
            plannedBlockIndices: planned,
            runStart: now,
            targetEnd: dayEnd
        )
        deriveBlockStates()
    }

    @MainActor
    func startTimelessDay() {
        guard dayEngineMode == .taskLed, classicDayScheduleStyle == .timeless else { return }
        let now = Date()
        currentTime = now
        let planned = blocks.indices.filter { blocks[$0].state != .skipped }
        let totalMinutes = planned.reduce(0) { partialResult, index in
            partialResult + max(blocks[index].durationMinutes, 1)
        }
        guard
            let dayEnd = calendar.date(byAdding: .minute, value: totalMinutes, to: now),
            dayEnd > now
        else {
            return
        }
        startTimelessRun(dayEnd: dayEnd)
    }

    @MainActor
    func finishActiveBlock() {
        if dayEngineMode == .formulaBased {
            finishFormulaBlock()
            return
        }

        guard classicDayScheduleStyle == .timeless, timelessRunStartedAt != nil else { return }
        guard let index = blocks.firstIndex(where: { $0.state == .active }) else { return }
        let now = Date()
        currentTime = now
        markBlockTasksCompleted(at: index)
        blocks[index].state = .completed

        let tail = blocks.indices.filter { indexToCheck in
            indexToCheck > index && blocks[indexToCheck].state != .skipped && blocks[indexToCheck].state != .completed
        }
        if let dayEnd = timelessTargetDayEnd, !tail.isEmpty, now < dayEnd {
            applyTimelessPlan(
                plannedBlockIndices: Array(tail),
                runStart: now,
                targetEnd: dayEnd
            )
        } else {
            rescheduleTailAfterCompletion(completedIndex: index, from: now)
        }
        sealLiveProgressiveAdvanceAfterManualBlockComplete()
    }

    @MainActor
    func selectFormula(_ formulaID: UUID) {
        guard availableFormulas.contains(where: { $0.id == formulaID }) else { return }
        selectedFormulaID = formulaID
        Self.persistFormulaSelection(formulaID)
        formulaBlocks = []
        formulaSchedulePausedAt = nil
        formulaRunStartedAt = nil
        formulaStoppedAt = nil
        formulaTargetDayEnd = nil
        formulaNominalMinutesByBlockID.removeAll()
        futurePinnedFormulaBlocks.removeAll()
        clearPersistedFormulaRuntimeState()
        removeScheduleInjectionsFromTimeline()
        anchorClaimedCardIDs.removeAll(keepingCapacity: true)

        if dayEngineMode == .formulaBased {
            prepareFormulaPreview()
        }
    }

    @MainActor
    @discardableResult
    func saveCreatedFormula(_ formula: DayFormulaTemplate) -> Bool {
        guard FormulaLibraryService.saveCustomSchedule(formula) else { return false }
        availableFormulas = FormulaLibraryService.allSchedules
        selectFormula(formula.id)
        return true
    }

    /// Rebuilds the preview timeline from accordion drafts (before the schedule starts).
    @MainActor
    func replacePreviewBlocksFromDrafts(_ drafts: [ScheduleBlockDraft]) {
        guard isFormulaPreviewing, selectedFormula != nil else { return }
        let templates = drafts
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { $0.toFormulaBlockTemplate() }
        guard !templates.isEmpty else { return }

        guard let base = selectedFormula else { return }
        let totalM = templates.reduce(0) { $0 + max($1.durationMinutes, 1) }
        let tempFormula = DayFormulaTemplate(
            id: base.id,
            name: base.name,
            symbol: base.symbol,
            summary: "\(templates.count) \(templates.count == 1 ? "block" : "blocks") · \(ScheduleBlockFormat.durationLabel(minutes: totalM))",
            targetDurationMinutes: max(base.targetDurationMinutes, totalM, 5),
            rules: base.rules,
            blocks: templates
        )
        let anchor = Date()
        blocks = materializedFormulaBlocks(formula: tempFormula, anchor: anchor, fillsFromExecution: false)
        snapshotFormulaNominals()
        formulaBlocks = blocks
        deriveBlockStates()
        persistCurrentBlocks()
        markFormulaPreviewScheduleStructureChangedIfPreviewing()
    }

    /// Creates a new user-saved algorithm from a starter block and selects it for inline editing.
    @MainActor
    func createNewUserAlgorithmFromRoutineTemplate() {
        let draft = ScheduleBlockDraft.routineTemplate()
        let blockTemplate = draft.toFormulaBlockTemplate().copyWithNewID()
        let totalM = max(1, blockTemplate.durationMinutes)
        let uniqueName = FormulaLibraryService.uniquedScheduleDisplayName(startingWith: "Untitled blocks", excludingScheduleID: nil)
        let formula = DayFormulaTemplate(
            id: UUID(),
            name: uniqueName,
            symbol: "calendar",
            summary: "1 block · \(ScheduleBlockFormat.durationLabel(minutes: totalM))",
            targetDurationMinutes: max(5, totalM),
            rules: [],
            blocks: [blockTemplate]
        )
        guard FormulaLibraryService.saveCustomSchedule(formula) else { return }
        availableFormulas = FormulaLibraryService.allSchedules
        selectFormula(formula.id)
    }

    /// Persists the current preview blocks to the formula library.
    @MainActor
    @discardableResult
    func saveCurrentPreviewSchedule(
        name: String,
        symbol: String,
        summary userSummary: String,
        intent: FormulaScheduleSaveIntent
    ) -> Bool {
        guard isFormulaPreviewing else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        let blockTemplates = blockTemplatesForLibrarySaveFromPreview()
        guard !blockTemplates.isEmpty else { return false }

        let customIDs = Set(FormulaLibraryService.customSchedules().map(\.id))
        let isUserCustom = selectedFormulaID.map { customIDs.contains($0) } ?? false

        let formulaID: UUID
        switch intent {
        case .updateExisting:
            guard isUserCustom, let sid = selectedFormulaID else { return false }
            formulaID = sid
        case .saveAsNew:
            formulaID = UUID()
        }

        let nameExclusionForUniqueness: UUID? = (intent == .updateExisting) ? formulaID : nil
        if FormulaLibraryService.existingScheduleConflictingWithName(trimmedName, excludingScheduleID: nameExclusionForUniqueness) != nil {
            return false
        }

        let totalM = blockTemplates.reduce(0) { $0 + max($1.durationMinutes, 1) }
        let rules = selectedFormula?.rules ?? []

        let summaryTrimmed = userSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let autoSummary = "\(blockTemplates.count) \(blockTemplates.count == 1 ? "block" : "blocks") · \(ScheduleBlockFormat.durationLabel(minutes: totalM))"
        let summary = summaryTrimmed.isEmpty ? autoSummary : summaryTrimmed

        let formula = DayFormulaTemplate(
            id: formulaID,
            name: trimmedName,
            symbol: symbol,
            summary: summary,
            targetDurationMinutes: max(totalM, 5),
            rules: rules,
            blocks: blockTemplates
        )
        guard FormulaLibraryService.saveCustomSchedule(formula) else { return false }
        availableFormulas = FormulaLibraryService.allSchedules
        selectFormula(formula.id)
        return true
    }

    // MARK: - Formula preview save visibility (explicit user edits)

    private struct FormulaScheduleTaskSemanticSnapshot: Codable, Equatable {
        var title: String
        var isPrimary: Bool
        var isRepeating: Bool
        var plannerTaskItemID: UUID?
        var field: String?
        var project: String?
        var folder: String?

        init(task: DayTask) {
            title = task.title
            isPrimary = task.isPrimary
            isRepeating = task.isRepeating
            plannerTaskItemID = task.plannerTaskItemID
            field = task.field
            project = task.project
            folder = task.folder
        }
    }

    private struct FormulaScheduleBlockSemanticSnapshot: Codable, Equatable {
        var title: String
        var type: BlockType
        var durationMinutes: Int
        var flowMode: BlockFlowMode
        var taskSource: ScheduleBlockTaskSource
        var fillMatchesType: BlockType?
        var fillRule: ScheduleFillRule?
        var tasks: [FormulaScheduleTaskSemanticSnapshot]
        var isRepeatable: Bool
        var pinsToClock: Bool
        var fixedClockMinutesFromDayStart: Int?
        var schedulingPriority: Int?
        var compactPresentation: Bool
        var locksPlannedDuration: Bool
        var timelineGlyph: String?
        var timelineAccentHex: UInt32?

        init(template: DayFormulaBlockTemplate) {
            title = template.title
            type = template.type
            durationMinutes = template.durationMinutes
            flowMode = template.flowMode
            taskSource = template.taskSource
            fillMatchesType = template.fillMatchesType
            fillRule = template.fillRule
            tasks = template.tasks.map { FormulaScheduleTaskSemanticSnapshot(task: $0) }
            isRepeatable = template.isRepeatable
            pinsToClock = template.pinsToClock
            fixedClockMinutesFromDayStart = template.fixedClockMinutesFromDayStart
            schedulingPriority = template.schedulingPriority
            compactPresentation = template.compactPresentation
            locksPlannedDuration = template.locksPlannedDuration
            timelineGlyph = template.timelineGlyph
            timelineAccentHex = template.timelineAccentHex
        }
    }

    /// Blocks that define the saved schedule shape (library / dirty checks). Uses full in-memory preview
    /// strips so eligibility for the Today timeline (e.g. calendar-day filtering) cannot flip “dirty”
    /// or hide Save when the user has not actually edited the schedule.
    @MainActor
    private func scheduleBlocksForLibraryTemplateRoundTrip() -> [DayBlock] {
        blocks.filter { !$0.isAnchorBlock }.sorted { $0.startTime < $1.startTime }
    }

    @MainActor
    private func blockTemplatesForLibrarySaveFromPreview() -> [DayFormulaBlockTemplate] {
        scheduleBlocksForLibraryTemplateRoundTrip().compactMap { block in
            let draft = ScheduleBlockDraft(from: block)
            let t = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            return draft.toFormulaBlockTemplate()
        }
    }

    private func libraryTemplateFingerprint(_ templates: [DayFormulaBlockTemplate]) -> String {
        let snapshots = templates.map { FormulaScheduleBlockSemanticSnapshot(template: $0) }
        let data = (try? JSONEncoder().encode(snapshots)) ?? Data()
        return data.base64EncodedString()
    }

    @MainActor
    private func previewBlockTemplatesMatchSelectedLibraryDefinition() -> Bool {
        guard let def = selectedFormula?.blocks else { return false }
        return libraryTemplateFingerprint(def) == libraryTemplateFingerprint(blockTemplatesForLibrarySaveFromPreview())
    }

    @MainActor
    private func markFormulaPreviewScheduleStructureChangedIfPreviewing() {
        guard isFormulaPreviewing else { return }
        formulaPreviewStructureEditGeneration += 1
    }

    @MainActor
    private func resetFormulaPreviewStructureChangeTrackingToClean() {
        formulaPreviewStructureCleanGeneration = formulaPreviewStructureEditGeneration
    }

    /// After undo restores blocks, clear “dirty” if the preview again matches the selected library template.
    @MainActor
    private func reconcileFormulaPreviewDirtyGenerationAfterUndoIfNeeded() {
        guard isFormulaPreviewing else { return }
        if previewBlockTemplatesMatchSelectedLibraryDefinition() {
            resetFormulaPreviewStructureChangeTrackingToClean()
        }
    }

    @MainActor
    func startFormulaDay() {
        startFormulaDay(targetEnd: nil)
    }

    @MainActor
    func startFormulaDay(targetEnd requestedTargetEnd: Date?) {
        guard dayEngineMode == .formulaBased else { return }
        let formula = selectedFormula

        if isFormulaRunStopped {
            resumeFormulaDay()
            return
        }

        let now = Date()
        currentTime = now
        formulaSchedulePausedAt = nil

        // Clear any stale Schedule → Timeline projections before rebuilding the run.
        removeScheduleInjectionsFromTimeline()
        anchorClaimedCardIDs.removeAll(keepingCapacity: true)

        // 1. Snapshot timeline anchors → feed them into the schedule later.
        let anchorBlocks = collectTimelineAnchorsAsScheduleBlocks()
        anchorClaimedCardIDs = Set(anchorBlocks.compactMap(\.anchorExecutionCardID))

        // 2. Materialize formula blocks (fills pull from pool; anchors excluded).
        let sourceBlocks: [DayBlock]
        if blocks.isEmpty, let formula {
            sourceBlocks = formula.materializeDay(startingAt: now)
        } else {
            sourceBlocks = blocks.filter { !$0.isAnchorBlock }
        }
        stashFuturePinnedFormulaBlocks(sourceBlocks, relativeTo: now)
        let todaySourceBlocks = todayEligibleScheduleBlocks(from: sourceBlocks, relativeTo: now)
        guard !todaySourceBlocks.isEmpty else { return }
        let fillsFromExecution = TodayDisplayPreferences.pullsTasksFromExecutionPoolPreference()
        blocks = materializedScheduleBlocks(from: todaySourceBlocks, anchor: now, fillsFromExecution: fillsFromExecution)
        snapshotFormulaNominals(adjustForPriority: true)
        formulaRunStartedAt = now
        formulaStoppedAt = nil

        let sourceTargetMinutes = todaySourceBlocks.reduce(0) { $0 + max($1.durationMinutes, 1) }
        let nominalForDefaultEnd = max(
            formula?.targetDurationMinutes ?? 0,
            formula?.totalNominalMinutes ?? 0,
            sourceTargetMinutes,
            60
        )
        // Match the preview timeline width (includes idle gaps before clock-pinned blocks), not just ∑ durations.
        let defaultTargetEnd = defaultScheduleTargetEnd(for: blocks, runStart: now, nominalMinutes: nominalForDefaultEnd)
        if let requestedTargetEnd, requestedTargetEnd > now {
            formulaTargetDayEnd = requestedTargetEnd
        } else {
            formulaTargetDayEnd = defaultTargetEnd
        }

        let planned = blocks.indices.filter { blocks[$0].state != .skipped }
        if let targetEnd = formulaTargetDayEnd, !planned.isEmpty {
            reflowFormulaBlocksAroundFixedTimes(
                plannedBlockIndices: planned,
                runStart: now,
                targetEnd: targetEnd
            )
        }

        // 3. Pin anchors into the Schedule at their timeline times.
        mergeAnchorBlocksIntoSchedule(anchorBlocks)

        // 4. Project Schedule's routines / fixed-template blocks onto the Timeline.
        injectScheduleBlocksIntoTimeline()

        deriveBlockStates()
        lastFormulaBlockDeriveAt = currentTime
    }

    @MainActor
    func restartFormulaDay() {
        guard dayEngineMode == .formulaBased else { return }
        removeScheduleInjectionsFromTimeline()
        anchorClaimedCardIDs.removeAll(keepingCapacity: true)
        clearPersistedFormulaRuntimeState()
        prepareFormulaPreview()
    }

    /// Stops any run, detaches the schedule template, and clears Today’s schedule blocks.
    @MainActor
    func clearSchedule() {
        guard dayEngineMode == .formulaBased else { return }
        if isFormulaRunLive {
            stopFormulaDay()
        }
        selectedFormulaID = nil
        Self.persistFormulaSelection(nil)
        futurePinnedFormulaBlocks.removeAll()
        restartFormulaDay()
    }

    @MainActor
    func stopFormulaDay() {
        guard dayEngineMode == .formulaBased, formulaRunStartedAt != nil else { return }
        formulaSchedulePausedAt = nil
        currentTime = Date()
        formulaRunStartedAt = nil
        formulaStoppedAt = currentTime
        removeScheduleInjectionsFromTimeline()
        anchorClaimedCardIDs.removeAll(keepingCapacity: true)
        if normalizeUnstartedStoppedFormulaRunIfNeeded() { return }
        persistCurrentBlocks()
        restartExecutionTimerIfNeeded()
    }

    @MainActor
    private func resumeFormulaDay() {
        guard dayEngineMode == .formulaBased, formulaStoppedAt != nil else { return }

        let now = Date()
        let pausedAt = formulaStoppedAt ?? now
        currentTime = now

        shiftFormulaScheduleAfterElapsedPause(pausedAt: pausedAt, resumeNow: now)

        formulaRunStartedAt = now
        formulaStoppedAt = nil
        if !TodayDisplayPreferences.pullsTasksFromExecutionPoolPreference() {
            clearExecutionFillAssignmentsFromSchedule()
        }
        deriveBlockStates()
        lastFormulaBlockDeriveAt = currentTime
    }

    /// Shifts incomplete formula blocks forward after time spent stopped or paused (same rules as Settings “pause behavior”).
    private func shiftFormulaScheduleAfterElapsedPause(pausedAt: Date, resumeNow: Date) {
        let pauseDuration = max(0, resumeNow.timeIntervalSince(pausedAt))
        let pauseBehavior = TodayDisplayPreferences.schedulePauseBehaviorPreference()

        if pauseBehavior == .preserveLength {
            resumeFormulaDayPreservingDurations(from: pausedAt, at: resumeNow, pauseDuration: pauseDuration)
        } else if let activeIndex = blocks.firstIndex(where: { $0.state == .active }) {
            let remaining = blocks.indices.filter { index in
                index >= activeIndex
                    && blocks[index].state != .completed
                    && blocks[index].state != .skipped
            }
            for index in remaining {
                blocks[index].state = index == activeIndex ? .active : .upcoming
            }
            reflowFormulaBlocksAroundFixedTimes(
                plannedBlockIndices: Array(remaining),
                runStart: resumeNow,
                targetEnd: effectiveFormulaTargetEnd(from: resumeNow)
            )
        } else if let firstUpcomingIndex = blocks.firstIndex(where: { $0.state == .upcoming }) {
            let remaining = blocks.indices.filter { $0 >= firstUpcomingIndex && blocks[$0].state == .upcoming }
            reflowFormulaBlocksAroundFixedTimes(
                plannedBlockIndices: Array(remaining),
                runStart: resumeNow,
                targetEnd: effectiveFormulaTargetEnd(from: resumeNow)
            )
        }
    }

    @MainActor
    func pauseFormulaSchedule() {
        guard dayEngineMode == .formulaBased else { return }
        guard isFormulaRunLive, formulaSchedulePausedAt == nil else { return }
        formulaSchedulePausedAt = Date()
        deriveBlockStates()
    }

    @MainActor
    func resumeFormulaScheduleAfterPause() {
        guard dayEngineMode == .formulaBased else { return }
        guard let pausedAt = formulaSchedulePausedAt else { return }
        formulaSchedulePausedAt = nil
        let now = Date()
        currentTime = now
        shiftFormulaScheduleAfterElapsedPause(pausedAt: pausedAt, resumeNow: now)
        if !TodayDisplayPreferences.pullsTasksFromExecutionPoolPreference() {
            clearExecutionFillAssignmentsFromSchedule()
        }
        deriveBlockStates()
        lastFormulaBlockDeriveAt = currentTime
    }

    private func resumeFormulaDayPreservingDurations(from pausedAt: Date, at resumeDate: Date, pauseDuration: TimeInterval) {
        let remaining: [Int]
        if let activeIndex = blocks.firstIndex(where: { $0.state == .active }) {
            remaining = blocks.indices.filter { index in
                index >= activeIndex
                    && blocks[index].state != .completed
                    && blocks[index].state != .skipped
            }
        } else if let firstUpcomingIndex = blocks.firstIndex(where: { $0.state == .upcoming }) {
            remaining = blocks.indices.filter { $0 >= firstUpcomingIndex && blocks[$0].state == .upcoming }
        } else {
            remaining = []
        }

        guard !remaining.isEmpty else {
            if pauseDuration > 0, let targetEnd = formulaTargetDayEnd {
                formulaTargetDayEnd = targetEnd.addingTimeInterval(pauseDuration)
            }
            return
        }

        var cursor = resumeDate
        for (offset, index) in remaining.enumerated() {
            let originalRemainingSeconds: TimeInterval
            if blocks[index].state == .active {
                originalRemainingSeconds = max(1, blocks[index].endTime.timeIntervalSince(pausedAt))
            } else {
                originalRemainingSeconds = max(1, blocks[index].endTime.timeIntervalSince(blocks[index].startTime))
            }

            blocks[index].state = offset == 0 ? .active : .upcoming
            blocks[index].startTime = cursor
            blocks[index].endTime = cursor.addingTimeInterval(originalRemainingSeconds)
            cursor = blocks[index].endTime
        }

        if let targetEnd = formulaTargetDayEnd {
            formulaTargetDayEnd = max(targetEnd.addingTimeInterval(pauseDuration), cursor)
        } else {
            formulaTargetDayEnd = cursor
        }
    }

    @MainActor
    func canRearrangeFormulaBlock(blockID: UUID) -> Bool {
        guard dayEngineMode == .formulaBased else { return false }
        guard let _ = blocks.first(where: { $0.id == blockID }) else { return false }
        return true
    }

    @MainActor
    @discardableResult
    func moveFormulaBlock(sourceID: UUID, before targetID: UUID?) -> Bool {
        guard dayEngineMode == .formulaBased else { return false }
        guard canRearrangeFormulaBlock(blockID: sourceID) else { return false }
        guard let sourceIndex = blocks.firstIndex(where: { $0.id == sourceID }) else { return false }
        if let t = targetID, t == sourceID { return false }
        if let targetID, !canRearrangeFormulaBlock(blockID: targetID) { return false }

        if let t = targetID {
            guard let tIndex = blocks.firstIndex(where: { $0.id == t }) else { return false }
            if tIndex - 1 == sourceIndex { return false }
        } else if sourceIndex == blocks.count - 1 {
            return false
        }

        if let candidate = formulaMoveCandidateOrder(sourceID: sourceID, before: targetID) {
            let baselineViolationCount = clockAnchoredFixedTimeInversionCount(in: blocks)
            let candidateViolationCount = clockAnchoredFixedTimeInversionCount(in: candidate)
            if candidateViolationCount > baselineViolationCount,
               let violation = clockAnchoredFixedTimeOrderViolation(in: candidate) {
                showClockAnchoredFixedTimeOrderViolationToast(
                    laterListedFirst: violation.laterListedFirst,
                    earlierListedSecond: violation.earlierListedSecond
                )
                return false
            }
        }

        // Manual rearrange should not be blocked by tiny-block heuristics.
        // The hard rule is fixed/anchor clock order; all other moves are allowed.

        let idsBefore = blocks.map(\.id)
        CueInHaptics.listRowMoved()

        withAnimation(
            .spring(
                response: 0.38,
                dampingFraction: 0.86,
                blendDuration: 0.02
            )
        ) {
            let movingBlock = blocks.remove(at: sourceIndex)
            let targetIndex = targetID.flatMap { id in
                blocks.firstIndex(where: { $0.id == id })
            }

            if let targetIndex {
                blocks.insert(movingBlock, at: targetIndex)
            } else {
                blocks.append(movingBlock)
            }

            if blocks.map(\.id) != idsBefore {
                if isFormulaRunLive {
                    restartLiveFormulaFlowFromCurrentOrder()
                } else if isFormulaRunStopped {
                    rescheduleStoppedFormulaAfterReorder()
                }
            }

            deriveBlockStates()
        }
        if isFormulaPreviewing, blocks.map(\.id) != idsBefore {
            markFormulaPreviewScheduleStructureChangedIfPreviewing()
        }
        return true
    }

    @MainActor
    func canUseBlockContextMenu(blockID: UUID) -> Bool {
        guard dayEngineMode == .formulaBased else { return false }
        return blocks.contains(where: { $0.id == blockID })
    }

    @MainActor
    func canDeleteFormulaBlock(blockID: UUID) -> Bool {
        guard canUseBlockContextMenu(blockID: blockID) else { return false }
        return blocks.contains(where: { $0.id == blockID })
    }

    private struct FormulaMoveConflict {
        let sourceID: UUID
        let targetID: UUID?
        let splitFixedID: UUID?
        let sourceTitle: String
        let boundaryTitle: String
        let predictedMinutes: Int
        let minimumMinutes: Int
        let windowMinutes: Int
    }

    private func liveMoveConflict(sourceID: UUID, before targetID: UUID?) -> FormulaMoveConflict? {
        guard isFormulaRunLive || isFormulaRunStopped else { return nil }
        guard TodayDisplayPreferences.avoidTinyBlocksPreference() else { return nil }
        guard TodayDisplayPreferences.protectFixedTimeBlocksPreference() else { return nil }
        guard let candidate = formulaMoveCandidateOrder(sourceID: sourceID, before: targetID),
              let source = candidate.first(where: { $0.id == sourceID }),
              !isFixedTimeScheduleBlock(source)
        else { return nil }

        let runStart = isFormulaRunStopped ? (formulaStoppedAt ?? currentTime) : currentTime
        let planned = formulaMovePlannedBlocks(in: candidate, runStart: runStart)
        guard planned.contains(where: { $0.id == sourceID }) else { return nil }

        var cursor = runStart
        var flexibleSegment: [DayBlock] = []
        var sourceConflict: FormulaMoveConflict?

        func inspectSegment(endingAt segmentEnd: Date?, boundary: DayBlock?) {
            guard sourceConflict == nil, !flexibleSegment.isEmpty else { return }
            guard flexibleSegment.contains(where: { $0.id == sourceID }) else { return }
            guard let segmentEnd, segmentEnd > cursor else {
                sourceConflict = makeFormulaMoveConflict(
                    source: source,
                    targetID: targetID,
                    splitFixedID: boundary?.id,
                    boundaryTitle: boundary?.title ?? "the schedule end",
                    predictedSeconds: 0,
                    windowSeconds: 0
                )
                return
            }

            let weights = formulaPlanningNominalMinutesByBlockID()
            let totalWeight = flexibleSegment.reduce(0.0) { total, block in
                total + Double(max(weights[block.id] ?? max(block.durationMinutes, 1), 1))
            }
            guard totalWeight > 0 else { return }

            let windowSeconds = segmentEnd.timeIntervalSince(cursor)
            let sourceWeight = Double(max(weights[sourceID] ?? max(source.durationMinutes, 1), 1))
            let predictedSeconds = windowSeconds * sourceWeight / totalWeight
            let minimumSeconds = TimeInterval(minimumAllowedMinutes(for: source) * 60)

            if predictedSeconds < minimumSeconds {
                sourceConflict = makeFormulaMoveConflict(
                    source: source,
                    targetID: targetID,
                    splitFixedID: boundary?.id,
                    boundaryTitle: boundary?.title ?? "the schedule end",
                    predictedSeconds: predictedSeconds,
                    windowSeconds: windowSeconds
                )
            }
        }

        for block in planned {
            if isFixedTimeScheduleBlock(block) {
                inspectSegment(endingAt: block.startTime, boundary: block)
                flexibleSegment.removeAll()
                if block.endTime > cursor {
                    cursor = block.endTime
                }
            } else {
                flexibleSegment.append(block)
            }
        }

        if let targetEnd = effectiveFormulaTargetEnd(from: cursor) {
            inspectSegment(endingAt: targetEnd, boundary: nil)
        }
        return sourceConflict
    }

    private func formulaMoveCandidateOrder(sourceID: UUID, before targetID: UUID?) -> [DayBlock]? {
        guard let sourceIndex = blocks.firstIndex(where: { $0.id == sourceID }) else { return nil }
        var candidate = blocks
        let moving = candidate.remove(at: sourceIndex)
        if let targetID,
           let targetIndex = candidate.firstIndex(where: { $0.id == targetID }) {
            candidate.insert(moving, at: targetIndex)
        } else {
            candidate.append(moving)
        }
        return candidate
    }

    private func formulaMovePlannedBlocks(in orderedBlocks: [DayBlock], runStart: Date) -> [DayBlock] {
        if isFormulaRunLive {
            guard let first = orderedBlocks.firstIndex(where: {
                $0.state != .completed && $0.state != .skipped
            }) else { return [] }
            return orderedBlocks[first...].filter { $0.state != .completed && $0.state != .skipped }
        }

        if isFormulaRunStopped {
            return orderedBlocks.filter { $0.state == .active || $0.state == .upcoming }
        }

        _ = runStart
        return orderedBlocks
    }

    private func minimumAllowedMinutes(for block: DayBlock) -> Int {
        let nominal = formulaNominalMinutesByBlockID[block.id] ?? max(block.durationMinutes, 1)
        if block.locksPlannedDuration {
            return max(1, nominal)
        }
        let configuredMinimum = TodayDisplayPreferences.minimumFlexibleBlockMinutesPreference()
        return max(1, min(configuredMinimum, nominal))
    }

    private func makeFormulaMoveConflict(
        source: DayBlock,
        targetID: UUID?,
        splitFixedID: UUID?,
        boundaryTitle: String,
        predictedSeconds: TimeInterval,
        windowSeconds: TimeInterval
    ) -> FormulaMoveConflict {
        return FormulaMoveConflict(
            sourceID: source.id,
            targetID: targetID,
            splitFixedID: splitFixedID,
            sourceTitle: source.title,
            boundaryTitle: boundaryTitle,
            predictedMinutes: max(0, Int(predictedSeconds / 60)),
            minimumMinutes: minimumAllowedMinutes(for: source),
            windowMinutes: max(0, Int(windowSeconds / 60))
        )
    }

    private func showFormulaMoveConflictWarning(_ conflict: FormulaMoveConflict) {
        let adjustedMinimum = max(5, conflict.predictedMinutes)
        var actions: [CueInToastActionModel] = []

        if let splitFixedID = conflict.splitFixedID {
            actions.append(
                CueInToastActionModel(title: "Split around fixed", systemImage: "rectangle.split.2x1") { [self] in
                    splitFormulaBlockAroundFixedTime(
                        sourceID: conflict.sourceID,
                        fixedID: splitFixedID,
                        before: conflict.targetID
                    )
                    CueInToastCenter.shared.dismiss()
                }
            )
        }

        actions.append(
            CueInToastActionModel(title: "Use \(adjustedMinimum)m min", systemImage: "slider.horizontal.3") {
                UserDefaults.standard.set(
                    Double(adjustedMinimum),
                    forKey: TodayDisplayPreferences.scheduleMinimumFlexibleBlockMinutes
                )
                CueInToastCenter.shared.dismiss()
            }
        )

        actions.append(
            CueInToastActionModel(title: "Allow tiny blocks", systemImage: "arrow.down.right.and.arrow.up.left") {
                UserDefaults.standard.set(
                    false,
                    forKey: TodayDisplayPreferences.scheduleAvoidTinyBlocks
                )
                CueInToastCenter.shared.dismiss()
            }
        )

        CueInToastCenter.shared.showWarning(
            icon: "exclamationmark.triangle.fill",
            title: "Fixed-time conflict",
            message: "“\(conflict.sourceTitle)” would get about \(conflict.predictedMinutes)m in a \(conflict.windowMinutes)m window before “\(conflict.boundaryTitle)”. Your minimum for that block is \(conflict.minimumMinutes)m.",
            actions: actions
        )
    }

    @MainActor
    private func splitFormulaBlockAroundFixedTime(sourceID: UUID, fixedID: UUID, before targetID: UUID?) {
        guard var candidate = formulaMoveCandidateOrder(sourceID: sourceID, before: targetID),
              let sourceIndex = candidate.firstIndex(where: { $0.id == sourceID }),
              let fixedIndex = candidate.firstIndex(where: { $0.id == fixedID }),
              sourceIndex < fixedIndex
        else { return }

        let source = candidate[sourceIndex]
        guard !isFixedTimeScheduleBlock(source) else { return }

        let nominalMinutes = max(formulaNominalMinutesByBlockID[source.id] ?? source.durationMinutes, 10)
        guard nominalMinutes > 10 else { return }

        let runStart = isFormulaRunStopped ? (formulaStoppedAt ?? currentTime) : currentTime
        let segmentStart = formulaSegmentStart(
            in: candidate,
            sourceIndex: sourceIndex,
            runStart: runStart
        )
        let fixedStart = candidate[fixedIndex].startTime
        let rawBeforeMinutes = max(0, Int(fixedStart.timeIntervalSince(segmentStart) / 60))
        let otherMinimums = candidate[sourceIndex..<fixedIndex].reduce(0) { total, block in
            guard block.id != sourceID, !isFixedTimeScheduleBlock(block) else { return total }
            return total + minimumAllowedMinutes(for: block)
        }
        let roomForFirstPart = max(0, rawBeforeMinutes - otherMinimums)
        let firstMinutes = min(nominalMinutes - 5, max(5, roomForFirstPart))
        guard firstMinutes < nominalMinutes else { return }

        let secondMinutes = nominalMinutes - firstMinutes
        let splitTasks = splitTasksForContinuation(source.tasks)

        var firstPart = source
        firstPart.tasks = splitTasks.first
        firstPart.endTime = calendar.date(
            byAdding: .minute,
            value: firstMinutes,
            to: firstPart.startTime
        ) ?? firstPart.endTime

        let secondPart = DayBlock(
            title: continuedTitle(for: source.title),
            type: source.type,
            state: .upcoming,
            startTime: candidate[fixedIndex].endTime,
            endTime: calendar.date(
                byAdding: .minute,
                value: secondMinutes,
                to: candidate[fixedIndex].endTime
            ) ?? candidate[fixedIndex].endTime,
            flowMode: source.flowMode,
            taskSource: source.taskSource,
            fillMatchesType: source.fillMatchesType,
            fillRule: source.fillRule,
            tasks: splitTasks.second,
            isRepeatable: source.isRepeatable,
            pinsToClock: source.pinsToClock,
            schedulingPriority: source.schedulingPriority,
            compactPresentation: source.compactPresentation,
            locksPlannedDuration: source.locksPlannedDuration,
            timelineGlyph: source.timelineGlyph,
            timelineAccentHex: source.timelineAccentHex
        )

        candidate[sourceIndex] = firstPart
        candidate.insert(secondPart, at: fixedIndex + 1)

        withAnimation(.spring(response: 0.36, dampingFraction: 0.88, blendDuration: 0.02)) {
            blocks = candidate
            formulaNominalMinutesByBlockID[source.id] = firstMinutes
            formulaNominalMinutesByBlockID[secondPart.id] = secondMinutes
            rechainFormulaTimesAfterStructuralEdit()
            deriveBlockStates()
            if isFormulaRunLive || isFormulaRunStopped {
                injectScheduleBlocksIntoTimeline()
            }
        }
        persistCurrentBlocks()
        if isFormulaPreviewing {
            markFormulaPreviewScheduleStructureChangedIfPreviewing()
        }
    }

    private func formulaSegmentStart(in orderedBlocks: [DayBlock], sourceIndex: Int, runStart: Date) -> Date {
        var cursor = runStart
        for index in orderedBlocks.indices where index < sourceIndex {
            let block = orderedBlocks[index]
            guard block.state != .completed && block.state != .skipped else { continue }
            if isFixedTimeScheduleBlock(block), block.endTime > cursor {
                cursor = block.endTime
            }
        }
        return cursor
    }

    private func splitTasksForContinuation(_ tasks: [DayTask]) -> (first: [DayTask], second: [DayTask]) {
        guard tasks.count > 1 else { return (tasks, []) }
        let splitIndex = Int(ceil(Double(tasks.count) / 2.0))
        return (Array(tasks.prefix(splitIndex)), Array(tasks.suffix(tasks.count - splitIndex)))
    }

    private func continuedTitle(for title: String) -> String {
        if title.localizedCaseInsensitiveContains("continued") {
            return title
        }
        return "\(title) (continued)"
    }

    @MainActor
    func unpinFormulaBlock(blockID: UUID) {
        ensureEditableFormulaBlocksForPreflight()
        guard canUseBlockContextMenu(blockID: blockID) else { return }
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        guard blocks[index].pinsToClock || blocks[index].isAnchorBlock else { return }

        let original = blocks[index]
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9, blendDuration: 0.02)) {
            blocks[index].pinsToClock = false
            blocks[index].anchorExecutionCardID = nil
            removeAnchorExecutionCardIfNeeded(for: original)
            rechainFormulaTimesAfterStructuralEdit()
            deriveBlockStates()
            if isFormulaRunLive || isFormulaRunStopped {
                injectScheduleBlocksIntoTimeline()
            }
        }
        persistCurrentBlocks()

        if isFormulaPreviewing {
            markFormulaPreviewScheduleStructureChangedIfPreviewing()
        }

        CueInToastCenter.shared.show(
            icon: "pin.slash.fill",
            title: "Pin removed",
            message: original.title,
            tint: CueInColors.warning,
            undoTitle: "Undo"
        ) { [self] in
            guard let restoreIndex = blocks.firstIndex(where: { $0.id == original.id }) else { return }
            blocks[restoreIndex] = original
            rechainFormulaTimesAfterStructuralEdit()
            deriveBlockStates()
            if isFormulaRunLive || isFormulaRunStopped {
                injectScheduleBlocksIntoTimeline()
            }
            persistCurrentBlocks()
            self.reconcileFormulaPreviewDirtyGenerationAfterUndoIfNeeded()
        }
    }

    @MainActor
    func deleteFormulaBlock(blockID: UUID) {
        ensureEditableFormulaBlocksForPreflight()
        guard canDeleteFormulaBlock(blockID: blockID) else { return }
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        let removed = blocks[index]
        let wasActive = isFormulaRunLive && removed.state == .active
        let savedNominal = formulaNominalMinutesByBlockID[blockID]

        withAnimation(
            .spring(
                response: 0.38,
                dampingFraction: 0.9,
                blendDuration: 0.02
            )
        ) {
            blocks.remove(at: index)
            removeAnchorExecutionCardIfNeeded(for: removed)
            formulaNominalMinutesByBlockID.removeValue(forKey: blockID)
            if !blocks.isEmpty {
                snapshotFormulaNominals()
                if isFormulaRunLive, wasActive {
                    restartLiveFormulaFlowFromCurrentOrder()
                } else {
                    rechainFormulaTimesAfterStructuralEdit()
                }
            }
            deriveBlockStates()
            if blocks.isEmpty {
                removeScheduleInjectionsFromTimeline()
            } else if isFormulaRunLive || isFormulaRunStopped {
                injectScheduleBlocksIntoTimeline()
            }
        }
        persistCurrentBlocks()

        CueInToastCenter.shared.show(
            icon: "trash.fill",
            title: "Block removed",
            message: removed.title,
            tint: Color(hex: 0x64A8FF)
        ) { [self] in
            self.restoreFormulaBlockAfterDeletion(removed, insertionIndex: index, savedNominal: savedNominal, wasActiveWhenDeleted: wasActive)
        }
        if isFormulaPreviewing {
            markFormulaPreviewScheduleStructureChangedIfPreviewing()
        }
    }

    @MainActor
    private func restoreFormulaBlockAfterDeletion(
        _ removed: DayBlock,
        insertionIndex: Int,
        savedNominal: Int?,
        wasActiveWhenDeleted: Bool
    ) {
        withAnimation(
            .spring(
                response: 0.38,
                dampingFraction: 0.9,
                blendDuration: 0.02
            )
        ) {
            let at = min(max(0, insertionIndex), blocks.count)
            blocks.insert(removed, at: at)
            if let savedNominal {
                formulaNominalMinutesByBlockID[removed.id] = savedNominal
            } else {
                formulaNominalMinutesByBlockID[removed.id] = max(1, max(removed.durationMinutes, 1))
            }
            snapshotFormulaNominals()
            if isFormulaRunLive, wasActiveWhenDeleted {
                restartLiveFormulaFlowFromCurrentOrder()
            } else {
                rechainFormulaTimesAfterStructuralEdit()
            }
            deriveBlockStates()
            if isFormulaRunLive || isFormulaRunStopped {
                injectScheduleBlocksIntoTimeline()
            }
        }
        persistCurrentBlocks()
        reconcileFormulaPreviewDirtyGenerationAfterUndoIfNeeded()
    }

    @MainActor
    private func ensureEditableFormulaBlocksForPreflight() {
        guard dayEngineMode == .formulaBased, blocks.isEmpty, selectedFormula != nil else { return }
        prepareFormulaPreview()
    }

    @MainActor
    func applyFormulaBlockEdits(
        blockID: UUID,
        title: String,
        type: BlockType,
        flowMode: BlockFlowMode,
        durationMinutes: Int
    ) {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        var draft = ScheduleBlockDraft(from: blocks[index])
        draft.title = title
        draft.timelineAccent = type
        draft.flowMode = flowMode
        draft.durationMinutes = durationMinutes
        applyFormulaBlockEdits(blockID: blockID, draft: draft)
    }

    /// Applies the shared block draft model (manual vs pool fill, tasks, filters, fixed-time length).
    @MainActor
    func applyFormulaBlockEdits(blockID: UUID, draft: ScheduleBlockDraft) {
        guard canUseBlockContextMenu(blockID: blockID) else { return }
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var effective = draft
        effective.id = blockID
        if effective.locksPlannedDuration {
            effective.schedulingPriority = nil
        }
        if blocks[index].isAnchorBlock {
            effective.assignsTasks = true
            effective.poolFillEnabled = false
        }
        let hasPinnedSourceTask = blocks[index].tasks.contains { $0.sourceExecutionTaskID != nil }
        let isDurationOverrideLocked = blocks[index].isAnchorBlock || hasPinnedSourceTask

        let wasActive = isFormulaRunLive && blocks[index].state == .active
        let plannedSecondsFromMinutes = max(5 * 60, min(blocks[index].durationMinutes * 60, 16 * 60 * 60))
        let existingWindowSeconds = max(
            5 * 60,
            min(Int(round(blocks[index].endTime.timeIntervalSince(blocks[index].startTime))), 16 * 60 * 60)
        )
        let existingSeconds = plannedSecondsFromMinutes
        let incomingSeconds = max(5 * 60, min(effective.liveDurationOverrideSeconds ?? (effective.durationMinutes * 60), 16 * 60 * 60))
        let attemptedDurationOverrideWhileLocked = isDurationOverrideLocked && incomingSeconds != existingSeconds
        let requestedSeconds = attemptedDurationOverrideWhileLocked ? existingSeconds : incomingSeconds
        let preserveActiveClockWindow = wasActive
            && !attemptedDurationOverrideWhileLocked
            && abs(requestedSeconds - existingWindowSeconds) <= 1
        let minutes = max(5, min(Int(round(Double(requestedSeconds) / 60.0)), 24 * 60))
        let previousTasks = blocks[index].tasks
        let newSource = effective.resolvedTaskSource

        withAnimation(
            .spring(
                response: 0.36,
                dampingFraction: 0.9,
                blendDuration: 0.02
            )
        ) {
            blocks[index].title = trimmed
            blocks[index].type = effective.timelineAccent
            blocks[index].pinsToClock = effective.pinsToClock
            blocks[index].schedulingPriority = effective.schedulingPriority
            blocks[index].compactPresentation = effective.compactPresentation
            blocks[index].locksPlannedDuration = effective.locksPlannedDuration
            blocks[index].timelineGlyph = effective.timelineGlyph
            blocks[index].timelineAccentHex = effective.timelineAccentHex
            blocks[index].flowMode = effective.flowMode
            blocks[index].taskSource = newSource
            blocks[index].fillMatchesType = nil
            blocks[index].fillRule = newSource == .executionFill ? effective.fillRule : nil
            blocks[index].isRepeatable = false

            if newSource == .templateTasks {
                blocks[index].tasks = effective.mergedDayTasks(previousTasks: previousTasks)
            } else if newSource == .executionFill {
                blocks[index].tasks = effective.mergedDayTasks(previousTasks: previousTasks)
            } else {
                blocks[index].tasks = []
            }

            formulaNominalMinutesByBlockID[blocks[index].id] = minutes

            if effective.pinsToClock,
               let clockMins = effective.fixedClockMinutesFromDayStart,
               !blocks[index].isAnchorBlock,
               !preserveActiveClockWindow {
                let dayStart = calendar.startOfDay(for: effective.fixedClockDate ?? blocks[index].startTime)
                blocks[index].startTime = calendar.date(byAdding: .minute, value: clockMins, to: dayStart)
                    ?? blocks[index].startTime
            }

            if isFixedTimeScheduleBlock(blocks[index]), !preserveActiveClockWindow {
                blocks[index].endTime = calendar.date(
                    byAdding: .minute,
                    value: minutes,
                    to: blocks[index].startTime
                ) ?? blocks[index].endTime
                updateAnchorExecutionCard(from: blocks[index])
            }

            if isFormulaRunLive {
                if wasActive {
                    if preserveActiveClockWindow {
                        // Metadata-only edit (e.g. blocking → flowing): keep the live clock window so the day
                        // doesn’t snap back to “fresh hour” starts or reshuffle the tail.
                        blocks[index].state = .active
                    } else {
                        // Keep the edited running block at the exact user-selected duration.
                        // Reflow only the tail afterwards so the active block doesn't get
                        // proportionally compressed back to an unexpected value.
                        let now = Date()
                        currentTime = now
                        blocks[index].state = .active
                        blocks[index].startTime = now
                        blocks[index].endTime = calendar.date(
                            byAdding: .second,
                            value: requestedSeconds,
                            to: now
                        ) ?? blocks[index].endTime

                        let tail = blocks.indices.filter { tailIndex in
                            tailIndex > index
                                && blocks[tailIndex].state != .completed
                                && blocks[tailIndex].state != .skipped
                        }

                        if !tail.isEmpty {
                            reflowFormulaBlocksAroundFixedTimes(
                                plannedBlockIndices: Array(tail),
                                runStart: blocks[index].endTime,
                                targetEnd: effectiveFormulaTargetEnd(from: now)
                            )
                        }
                    }
                } else {
                    rechainFormulaTimesAfterStructuralEdit()
                }
            } else if isFormulaRunStopped {
                rescheduleStoppedFormulaAfterReorder()
            } else {
                rechainFormulaTimesAfterStructuralEdit()
            }
            deriveBlockStates()
            snapshotFormulaNominals()
            if isFormulaRunLive || isFormulaRunStopped {
                injectScheduleBlocksIntoTimeline()
            }
        }

        if newSource == .executionFill,
           TodayDisplayPreferences.pullsTasksFromExecutionPoolPreference() {
            refillSchedulesFromPool()
        }

        if attemptedDurationOverrideWhileLocked {
            CueInToastCenter.shared.showWarning(
                icon: "pin.slash",
                title: "Duration locked by pinned task",
                message: "This block is anchored by a pinned task, so its duration can’t be overridden."
            )
        }

        persistCurrentBlocks()
        if isFormulaPreviewing {
            markFormulaPreviewScheduleStructureChangedIfPreviewing()
        }
    }

    @MainActor
    func renameFormulaBlock(blockID: UUID, title: String) {
        guard canUseBlockContextMenu(blockID: blockID) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        blocks[index].title = trimmed
        updateAnchorExecutionCard(from: blocks[index])
        if isFormulaRunLive || isFormulaRunStopped {
            injectScheduleBlocksIntoTimeline()
        }
        persistCurrentBlocks()
        if isFormulaPreviewing {
            markFormulaPreviewScheduleStructureChangedIfPreviewing()
        }
    }

    @MainActor
    @discardableResult
    func insertFormulaBlock(
        title: String,
        type: BlockType,
        flowMode: BlockFlowMode,
        durationMinutes: Int,
        tasks: [DayTask] = [],
        isRepeatable: Bool = false,
        after afterBlockID: UUID? = nil
    ) -> UUID? {
        guard dayEngineMode == .formulaBased else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let minutes = max(5, min(durationMinutes, 24 * 60))
        let insertionIndex = formulaInsertionIndex(after: afterBlockID)
        let start = formulaInsertionStartDate(for: insertionIndex)
        let end = calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
        let block = DayBlock(
            title: trimmed,
            type: type,
            state: .upcoming,
            startTime: start,
            endTime: end,
            flowMode: flowMode,
            taskSource: .templateTasks,
            tasks: tasks,
            isRepeatable: isRepeatable
        )

        withAnimation(
            .spring(response: 0.36, dampingFraction: 0.88, blendDuration: 0.02)
        ) {
            let safeIndex = min(max(insertionIndex, 0), blocks.count)
            blocks.insert(block, at: safeIndex)
            formulaNominalMinutesByBlockID[block.id] = minutes
            rechainFormulaTimesAfterStructuralEdit()
            deriveBlockStates()
            if isFormulaRunLive || isFormulaRunStopped {
                injectScheduleBlocksIntoTimeline()
            }
        }
        persistCurrentBlocks()
        if isFormulaPreviewing {
            markFormulaPreviewScheduleStructureChangedIfPreviewing()
        }

        CueInToastCenter.shared.show(
            icon: type.icon,
            title: "Block added",
            message: trimmed,
            tint: type.accent,
            undoTitle: "Undo"
        ) { [self] in
            self.deleteFormulaBlock(blockID: block.id)
        }

        return block.id
    }

    /// Inserts a block from the block library (saved or sample presets). Clock pins are cleared so the
    /// new slice chains cleanly with the rest of the formula.
    @MainActor
    @discardableResult
    func insertFormulaBlock(from template: DayFormulaBlockTemplate, after afterBlockID: UUID? = nil) -> UUID? {
        guard dayEngineMode == .formulaBased else { return nil }
        let fresh = template.copyWithNewID()
        let trimmed = fresh.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let blockID = fresh.id
        let minutes = max(5, min(fresh.durationMinutes, 24 * 60))
        let insertionIndex = formulaInsertionIndex(after: afterBlockID)
        let start = formulaInsertionStartDate(for: insertionIndex)
        let end = calendar.date(byAdding: .minute, value: minutes, to: start) ?? start

        let nestedTasks: [DayTask] = fresh.tasks.map { task in
            DayTask(
                id: UUID(),
                title: task.title,
                isCompleted: false,
                isPrimary: task.isPrimary,
                isRepeating: task.isRepeating,
                sourceExecutionBlockID: blockID,
                sourceExecutionTaskID: nil,
                plannerTaskItemID: task.plannerTaskItemID,
                field: task.field,
                project: task.project,
                folder: task.folder
            )
        }

        let effectiveTasks: [DayTask]
        switch fresh.taskSource {
        case .templateTasks:
            effectiveTasks = nestedTasks
        case .executionFill, .noTasks:
            effectiveTasks = []
        }

        let block = DayBlock(
            id: blockID,
            title: trimmed,
            type: fresh.type,
            state: .upcoming,
            startTime: start,
            endTime: end,
            flowMode: fresh.flowMode,
            taskSource: fresh.taskSource,
            fillMatchesType: fresh.fillMatchesType,
            fillRule: fresh.taskSource == .executionFill ? fresh.fillRule : nil,
            tasks: effectiveTasks,
            isRepeatable: fresh.isRepeatable,
            pinsToClock: false,
            schedulingPriority: fresh.schedulingPriority,
            compactPresentation: fresh.compactPresentation,
            locksPlannedDuration: fresh.locksPlannedDuration,
            timelineGlyph: fresh.timelineGlyph,
            timelineAccentHex: fresh.timelineAccentHex
        )

        withAnimation(
            .spring(response: 0.36, dampingFraction: 0.88, blendDuration: 0.02)
        ) {
            let safeIndex = min(max(insertionIndex, 0), blocks.count)
            blocks.insert(block, at: safeIndex)
            formulaNominalMinutesByBlockID[block.id] = minutes
            rechainFormulaTimesAfterStructuralEdit()
            deriveBlockStates()
            if isFormulaRunLive || isFormulaRunStopped {
                injectScheduleBlocksIntoTimeline()
            }
        }
        persistCurrentBlocks()

        if fresh.taskSource == .executionFill,
           TodayDisplayPreferences.pullsTasksFromExecutionPoolPreference() {
            refillSchedulesFromPool()
        }
        if isFormulaPreviewing {
            markFormulaPreviewScheduleStructureChangedIfPreviewing()
        }

        CueInToastCenter.shared.show(
            icon: fresh.type.icon,
            title: "Block added",
            message: trimmed,
            tint: fresh.type.accent,
            undoTitle: "Undo"
        ) { [self] in
            self.deleteFormulaBlock(blockID: block.id)
        }

        return block.id
    }

    private func formulaInsertionIndex(after afterBlockID: UUID?) -> Int {
        if let afterBlockID,
           let index = blocks.firstIndex(where: { $0.id == afterBlockID }) {
            return index + 1
        }
        if isFormulaRunLive || isFormulaRunStopped {
            if let activeIndex = blocks.firstIndex(where: { $0.state == .active }) {
                return activeIndex + 1
            }
            if let lastIncompleteIndex = blocks.lastIndex(where: {
                $0.state != .completed && $0.state != .skipped
            }) {
                return lastIncompleteIndex + 1
            }
        }
        return blocks.count
    }

    private func formulaInsertionStartDate(for insertionIndex: Int) -> Date {
        if insertionIndex > 0, blocks.indices.contains(insertionIndex - 1) {
            let previousEnd = blocks[insertionIndex - 1].endTime
            return isFormulaRunLive ? max(previousEnd, currentTime) : previousEnd
        }
        return isFormulaRunLive ? currentTime : (blocks.first?.startTime ?? currentTime)
    }

    @MainActor
    func addTemplateTaskToFormulaBlock(blockID: UUID, title: String) {
        guard canUseBlockContextMenu(blockID: blockID) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        blocks[index].tasks.append(
            DayTask(
                title: trimmed,
                isPrimary: false,
                sourceExecutionBlockID: blockID
            )
        )
        updateAnchorExecutionCard(from: blocks[index])
        if isFormulaRunLive || isFormulaRunStopped {
            injectScheduleBlocksIntoTimeline()
        }
        persistCurrentBlocks()
        if isFormulaPreviewing {
            markFormulaPreviewScheduleStructureChangedIfPreviewing()
        }
    }

    @MainActor
    private func rechainFormulaTimesAfterStructuralEdit() {
        if isFormulaRunLive {
            rescheduleFormulaAfterReorder()
        } else if isFormulaRunStopped {
            rescheduleStoppedFormulaAfterReorder()
        } else {
            let planned = Array(blocks.indices)
            guard let first = planned.first else { return }
            let start = blocks[first].startTime
            reflowFormulaBlocksAroundFixedTimes(
                plannedBlockIndices: planned,
                runStart: start,
                targetEnd: nil
            )
        }
    }

    /// Finish a block **and** mark every task inside it as complete.
    /// Use when the user explicitly says "done with everything".
    @MainActor
    func completeBlock(blockID: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        markBlockTasksCompleted(at: index)

        if dayEngineMode == .formulaBased || classicDayScheduleStyle == .timeless {
            if blocks[index].state == .active {
                finishActiveBlock()
                injectScheduleBlocksIntoTimeline()
                return
            }
        }

        blocks[index].state = .completed
        deriveBlockStates()
        injectScheduleBlocksIntoTimeline()
    }

    /// Finish a block *without* auto-completing pending tasks. Pending rows
    /// stay pending (they remain visible and are not ticked on the Timeline /
    /// TasksStore). Use when the user moves on but some tasks didn't happen.
    @MainActor
    func finishBlockKeepingPending(blockID: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }

        if dayEngineMode == .formulaBased || classicDayScheduleStyle == .timeless {
            if blocks[index].state == .active {
                finishActiveBlock()
                injectScheduleBlocksIntoTimeline()
                return
            }
        }

        blocks[index].state = .completed
        deriveBlockStates()
        injectScheduleBlocksIntoTimeline()
    }

    @MainActor
    func revertCompletedBlock(blockID: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        guard blocks[index].state == .completed else { return }

        for taskIndex in blocks[index].tasks.indices {
            blocks[index].tasks[taskIndex].isCompleted = false
        }
        blocks[index].state = .upcoming
        
        if isFormulaRunLive || isFormulaRunStopped {
            rechainFormulaTimesAfterStructuralEdit()
        }
        
        deriveBlockStates()
    }

    @MainActor
    func toggleTask(blockID: UUID, taskID: UUID) {
        guard
            let blockIndex = blocks.firstIndex(where: { $0.id == blockID }),
            let taskIndex = blocks[blockIndex].tasks.firstIndex(where: { $0.id == taskID })
        else {
            return
        }

        blocks[blockIndex].tasks[taskIndex].isCompleted.toggle()
        let updated = blocks[blockIndex].tasks[taskIndex]

        // Mirror into taskLead blocks (so mode switches stay consistent).
        syncExecutionTaskState(
            from: updated,
            fallbackBlockID: blockID,
            fallbackTaskID: taskID,
            isCompleted: updated.isCompleted
        )

        // Schedule → Timeline completion bridge:
        // 1. Fill-block rows correspond to a specific pool card. Tick it too.
        // 2. Routine-block rows don't map 1:1 to a card — we refresh the
        //    projected card's aggregate completion via re-injection.
        propagateScheduleTaskCompletionToTimeline(
            from: updated,
            inBlock: blocks[blockIndex]
        )

        injectScheduleBlocksIntoTimeline()
        persistCurrentBlocks()
    }

    /// When a DayTask is toggled inside a Schedule block, propagate the change
    /// to any Timeline card / TasksStore record it represents so both surfaces
    /// show the same completion state.
    @MainActor
    private func propagateScheduleTaskCompletionToTimeline(
        from task: DayTask,
        inBlock block: DayBlock
    ) {
        // Planner-backed pool rows (fill blocks) — update TasksStore and the
        // matching pool card on the Timeline.
        if let plannerID = task.plannerTaskItemID {
            TasksStore.shared.setCompletion(plannerID, completed: task.isCompleted)
            if let dayIndex = todayExecutionDayIndex,
               let cardIndex = executionDays[dayIndex].tasks.firstIndex(where: {
                   $0.plannerTaskItemID == plannerID
               }) {
                executionDays[dayIndex].tasks[cardIndex].isCompleted = task.isCompleted
            }
        }

        // Cards linked by id — covers fill blocks without a planner id and
        // any future ad-hoc injection.
        if let executionTaskID = task.sourceExecutionTaskID,
           let dayIndex = todayExecutionDayIndex,
           let cardIndex = executionDays[dayIndex].tasks.firstIndex(where: {
               $0.id == executionTaskID || $0.sourceTaskID == executionTaskID
           }) {
            executionDays[dayIndex].tasks[cardIndex].isCompleted = task.isCompleted
        }

        _ = block // referenced for future routing rules (e.g. anchor blocks).
    }

    @MainActor
    func toggleExecutionTask(dayID: Date, taskID: UUID) {
        guard let dayIndex = executionDays.firstIndex(where: { $0.id == dayID }) else { return }
        guard let taskIndex = executionDays[dayIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }

        executionDays[dayIndex].tasks[taskIndex].isCompleted.toggle()
        let updatedTask = executionDays[dayIndex].tasks[taskIndex]

        // Schedule-injected cards are a *projection* of a DayBlock. Toggling
        // completion on the Timeline should complete/uncomplete the whole
        // underlying block so both surfaces stay in lockstep.
        if let injectedBlockID = updatedTask.scheduleInjectedBlockID,
           let blockIndex = blocks.firstIndex(where: { $0.id == injectedBlockID }) {
            let nowCompleted = updatedTask.isCompleted
            for i in blocks[blockIndex].tasks.indices {
                blocks[blockIndex].tasks[i].isCompleted = nowCompleted
            }
            if let mirrorIndex = taskLeadBlocks.firstIndex(where: { $0.id == injectedBlockID }) {
                for i in taskLeadBlocks[mirrorIndex].tasks.indices {
                    taskLeadBlocks[mirrorIndex].tasks[i].isCompleted = nowCompleted
                }
            }
            persistCurrentBlocks()
            deriveBlockStates()
            return
        }

        if let sourceBlockID = updatedTask.sourceBlockID,
           let sourceTaskID = updatedTask.sourceTaskID,
           let blockIndex = taskLeadBlocks.firstIndex(where: { $0.id == sourceBlockID }),
           let sourceTaskIndex = taskLeadBlocks[blockIndex].tasks.firstIndex(where: { $0.id == sourceTaskID }) {
            taskLeadBlocks[blockIndex].tasks[sourceTaskIndex].isCompleted = updatedTask.isCompleted

            if let liveBlockIndex = blocks.firstIndex(where: { $0.id == sourceBlockID }),
               let liveTaskIndex = blocks[liveBlockIndex].tasks.firstIndex(where: { $0.id == sourceTaskID }) {
                blocks[liveBlockIndex].tasks[liveTaskIndex].isCompleted = updatedTask.isCompleted
            }

            syncScheduleTaskState(
                sourceExecutionBlockID: sourceBlockID,
                sourceExecutionTaskID: sourceTaskID,
                isCompleted: updatedTask.isCompleted
            )
        }

        // Planner-backed pool card: update TasksStore and every Schedule fill
        // block that currently holds this task so the Schedule reflects the
        // completion instantly.
        if let plannerID = updatedTask.plannerTaskItemID {
            TasksStore.shared.setCompletion(plannerID, completed: updatedTask.isCompleted)
            propagateTimelineCompletionToSchedule(
                plannerID: plannerID,
                cardID: updatedTask.id,
                isCompleted: updatedTask.isCompleted
            )
        } else {
            // Non-planner pool card (rare) — still propagate by card id.
            propagateTimelineCompletionToSchedule(
                plannerID: nil,
                cardID: updatedTask.id,
                isCompleted: updatedTask.isCompleted
            )
        }

        injectScheduleBlocksIntoTimeline()
    }

    /// Mirror a Timeline card's completion into any Schedule block that
    /// currently holds it as a DayTask (executionFill blocks). Matches by
    /// plannerTaskItemID first (stable), then falls back to card id.
    @MainActor
    private func propagateTimelineCompletionToSchedule(
        plannerID: UUID?,
        cardID: UUID,
        isCompleted: Bool
    ) {
        for blockIndex in blocks.indices {
            for taskIndex in blocks[blockIndex].tasks.indices {
                let match: Bool
                if let plannerID,
                   blocks[blockIndex].tasks[taskIndex].plannerTaskItemID == plannerID {
                    match = true
                } else if blocks[blockIndex].tasks[taskIndex].sourceExecutionTaskID == cardID {
                    match = true
                } else {
                    match = false
                }
                if match {
                    blocks[blockIndex].tasks[taskIndex].isCompleted = isCompleted
                }
            }
        }
    }

    @MainActor
    func deleteExecutionTask(dayID: Date, taskID: UUID) {
        guard let dayIndex = executionDays.firstIndex(where: { $0.id == dayID }) else { return }
        guard let task = executionDays[dayIndex].tasks.first(where: { $0.id == taskID }) else { return }

        // Injected schedule cards are owned by the Schedule — deleting the
        // block must happen from the Schedule surface, not the Timeline.
        guard !task.isScheduleInjected else { return }

        executionDays[dayIndex].tasks.removeAll { $0.id == taskID }

        if let sourceBlockID = task.sourceBlockID,
           let sourceTaskID = task.sourceTaskID,
           let blockIndex = taskLeadBlocks.firstIndex(where: { $0.id == sourceBlockID }) {
            taskLeadBlocks[blockIndex].tasks.removeAll { $0.id == sourceTaskID }

            if let liveBlockIndex = blocks.firstIndex(where: { $0.id == sourceBlockID }) {
                blocks[liveBlockIndex].tasks.removeAll { $0.id == sourceTaskID }
            }
        } else if let plannerID = task.plannerTaskItemID {
            TasksStore.shared.deleteTask(plannerID)
        }
    }

    // MARK: - Timeline Execution Controls

    /// Freezes task scheduling. While paused, real clock advances but task times are preserved.
    /// On resume, all future non-fixed tasks on today's timeline shift forward by the pause duration.
    @MainActor
    func pauseTimelineExecution() {
        guard !isExecutionPaused else { return }
        isExecutionPaused = true
        executionPausedAt = currentTime
    }

    /// Resumes execution after a pause, shifting non-fixed upcoming tasks forward by the elapsed pause duration.
    @MainActor
    func resumeTimelineExecution() {
        guard isExecutionPaused, let pausedAt = executionPausedAt else { return }
        let now = currentTime
        let delta = now.timeIntervalSince(pausedAt)

        defer {
            isExecutionPaused = false
            executionPausedAt = nil
        }

        guard delta > 0 else { return }
        guard let todayIndex = executionDays.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: now) }) else { return }

        for taskIndex in executionDays[todayIndex].tasks.indices {
            let task = executionDays[todayIndex].tasks[taskIndex]
            guard !task.isCompleted, !task.pinsToClock else { continue }
            if task.startDate >= pausedAt {
                executionDays[todayIndex].tasks[taskIndex].startDate =
                    task.startDate.addingTimeInterval(delta)
            }
        }
    }

    /// Snaps the first uncompleted, non-fixed task on today's timeline to start from now,
    /// cascading all subsequent tasks via the reflow engine.
    @MainActor
    func startTimelineExecution() {
        let now = currentTime
        guard let todayIndex = executionDays.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: now) }) else { return }

        let firstMovable = executionDays[todayIndex].tasks
            .filter { !$0.isCompleted && !$0.pinsToClock }
            .sorted { $0.startDate < $1.startDate }
            .first

        guard let task = firstMovable else { return }

        let dayStart = calendar.startOfDay(for: now)
        let reflowed = executionReflow.reflow(
            tasks: executionDays[todayIndex].tasks,
            change: .move(taskID: task.id, proposedStart: now, minimumMovableStart: now),
            dayStart: dayStart,
            calendar: calendar
        )
        executionDays[todayIndex].tasks = reflowed
    }

    // MARK: - Tasks tab → Today execution queue

    /// `true` if this planner task already has a row on today’s execution timeline.
    @MainActor
    func isPlannerTaskQueuedForToday(_ taskItemID: UUID) -> Bool {
        TasksStore.shared.todayTasks.contains { $0.id == taskItemID }
    }

    @MainActor
    func dequeuePlannerTask(_ taskItemID: UUID) {
        for dayIndex in executionDays.indices {
            executionDays[dayIndex].tasks.removeAll { $0.plannerTaskItemID == taskItemID }
        }
        TasksStore.shared.scheduleTask(taskItemID, on: nil)
    }

    /// Adds a planner task to **today’s** execution queue (Tasks tab lightning bolt),
    /// and schedules it for today in `TasksStore` so it shows under Today in Tasks.
    @MainActor
    func enqueuePlannerTask(_ item: TaskItem) {
        guard !item.isCompleted else { return }

        let todayStart = calendar.startOfDay(for: currentTime)
        TasksStore.shared.scheduleTask(item.id, on: todayStart)
        guard let dayIndex = executionDays.firstIndex(where: { calendar.isDate($0.id, inSameDayAs: todayStart) }) else {
            return
        }
        if executionDays[dayIndex].tasks.contains(where: { $0.plannerTaskItemID == item.id }) {
            return
        }

        let sorted = executionDays[dayIndex].tasks.sorted { $0.startDate < $1.startDate }
        let lastEnd = sorted.last.map(\.endDate) ?? todayStart
        let start = max(lastEnd, currentTime)
        let card = makeExecutionCard(from: item, start: start)

        executionDays[dayIndex].tasks.append(card)
        executionDays[dayIndex].tasks.sort { $0.startDate < $1.startDate }
    }

    @MainActor
    func dayID(containingExecutionTask taskID: UUID) -> Date? {
        executionDays.first(where: { day in
            day.tasks.contains(where: { $0.id == taskID })
        })?.id
    }

    @MainActor
    func completeExecutionTask(dayID: Date, taskID: UUID) {
        guard let dayIndex = executionDays.firstIndex(where: { $0.id == dayID }) else { return }
        guard let taskIndex = executionDays[dayIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        guard !executionDays[dayIndex].tasks[taskIndex].isCompleted else { return }
        toggleExecutionTask(dayID: dayID, taskID: taskID)
    }

    @MainActor
    func updateExecutionTask(dayID: Date, task: ExecutionTaskCard) {
        guard let dayIndex = executionDays.firstIndex(where: { $0.id == dayID }) else { return }
        guard let taskIndex = executionDays[dayIndex].tasks.firstIndex(where: { $0.id == task.id }) else { return }

        executionDays[dayIndex].tasks[taskIndex] = task
        executionDays[dayIndex].tasks.sort { $0.startDate < $1.startDate }

        if let sourceBlockID = task.sourceBlockID,
           let sourceTaskID = task.sourceTaskID,
           let blockIndex = taskLeadBlocks.firstIndex(where: { $0.id == sourceBlockID }),
           let sourceTaskIndex = taskLeadBlocks[blockIndex].tasks.firstIndex(where: { $0.id == sourceTaskID }) {
            taskLeadBlocks[blockIndex].tasks[sourceTaskIndex].title = task.title
            taskLeadBlocks[blockIndex].tasks[sourceTaskIndex].isPrimary = task.isPrimary
            taskLeadBlocks[blockIndex].tasks[sourceTaskIndex].isRepeating = task.isRepeating

            if let liveBlockIndex = blocks.firstIndex(where: { $0.id == sourceBlockID }),
               let liveTaskIndex = blocks[liveBlockIndex].tasks.firstIndex(where: { $0.id == sourceTaskID }) {
                blocks[liveBlockIndex].tasks[liveTaskIndex].title = task.title
                blocks[liveBlockIndex].tasks[liveTaskIndex].isPrimary = task.isPrimary
                blocks[liveBlockIndex].tasks[liveTaskIndex].isRepeating = task.isRepeating
            }
        } else if let plannerID = task.plannerTaskItemID {
            updatePlannerTask(from: task, plannerID: plannerID)
        }
    }

    @MainActor
    func previewExecutionTaskMove(dayID: Date, taskID: UUID, startDate: Date) -> [ExecutionTaskCard] {
        guard let day = executionDays.first(where: { $0.id == dayID }) else { return [] }
        guard day.tasks.contains(where: { $0.id == taskID }) else { return day.tasks }

        let dayStart = calendar.startOfDay(for: dayID)
        return executionReflow.reflow(
            tasks: day.tasks,
            change: .move(
                taskID: taskID,
                proposedStart: startDate,
                minimumMovableStart: minimumMovableStart(for: dayID)
            ),
            dayStart: dayStart,
            calendar: calendar
        )
    }

    @MainActor
    func moveExecutionTask(dayID: Date, taskID: UUID, startDate: Date) {
        guard let dayIndex = executionDays.firstIndex(where: { $0.id == dayID }) else { return }
        guard executionDays[dayIndex].tasks.contains(where: { $0.id == taskID }) else { return }

        let dayStart = calendar.startOfDay(for: dayID)
        let reflowed = executionReflow.reflow(
            tasks: executionDays[dayIndex].tasks,
            change: .move(
                taskID: taskID,
                proposedStart: startDate,
                minimumMovableStart: minimumMovableStart(for: dayID)
            ),
            dayStart: dayStart,
            calendar: calendar
        )
        executionDays[dayIndex].tasks = reflowed

        // If a Schedule run is live, fill blocks should reflect the new pool
        // order. Re-materialize only the `executionFill` blocks while keeping
        // all other block state + already-done task completion preserved.
        refillSchedulesFromPool()
    }

    /// When the execution pool changes (task moved, re-ordered, deleted, or
    /// added) we refresh every live `executionFill` block by re-running its
    /// fill rule. Completion of rows that still match the same planner id is
    /// preserved so finishing a task on one surface doesn't un-tick it after
    /// a pool reshuffle.
    @MainActor
    private func refillSchedulesFromPool() {
        guard TodayDisplayPreferences.pullsTasksFromExecutionPoolPreference() else { return }
        guard dayEngineMode == .formulaBased, isFormulaRunLive || isFormulaRunStopped else { return }

        // Snapshot completion keyed by plannerTaskItemID across all fill blocks.
        var previousCompletions: [UUID: Bool] = [:]
        for block in blocks where block.taskSource == .executionFill {
            for task in block.tasks {
                if let plannerID = task.plannerTaskItemID {
                    previousCompletions[plannerID] = task.isCompleted
                }
            }
        }

        // Re-run fills in block order so earlier blocks claim tasks first.
        var assigned = Set<UUID>()
        for blockIndex in blocks.indices where blocks[blockIndex].taskSource == .executionFill {
            let refilled = makeFilledScheduleTasks(
                for: blocks[blockIndex],
                assignedTaskIDs: &assigned
            )
            blocks[blockIndex].tasks = refilled.map { task in
                var t = task
                if let plannerID = t.plannerTaskItemID,
                   let was = previousCompletions[plannerID] {
                    t.isCompleted = was
                }
                return t
            }
        }

        injectScheduleBlocksIntoTimeline()
    }

    /// Reacts to `TodayDisplayPreferences.pullsTasksFromExecutionPool` changes from settings or menus.
    @MainActor
    func applyExecutionPoolPullPreference() {
        guard dayEngineMode == .formulaBased else { return }
        guard isFormulaRunLive || isFormulaRunStopped else { return }

        if TodayDisplayPreferences.pullsTasksFromExecutionPoolPreference() {
            refillSchedulesFromPool()
        } else {
            clearExecutionFillAssignmentsFromSchedule()
        }
    }

    private func clearExecutionFillAssignmentsFromSchedule() {
        var changed = false
        for i in blocks.indices where blocks[i].taskSource == .executionFill && !blocks[i].tasks.isEmpty {
            let manualOnly = blocks[i].tasks.filter { $0.sourceExecutionTaskID == nil }
            guard manualOnly.count != blocks[i].tasks.count else { continue }
            blocks[i].tasks = manualOnly
            changed = true
        }
        guard changed else { return }
        persistCurrentBlocks()
        injectScheduleBlocksIntoTimeline()
    }

    @MainActor
    func continueExecutionTaskNow(dayID: Date, taskID: UUID, additionalMinutes: Int = 15) {
        guard let dayIndex = executionDays.firstIndex(where: { $0.id == dayID }) else { return }
        guard let taskIndex = executionDays[dayIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        guard !executionDays[dayIndex].tasks[taskIndex].isCompleted else { return }

        executionDays[dayIndex].tasks[taskIndex].durationMinutes = max(additionalMinutes, 5)
        let reflowed = executionReflow.reflow(
            tasks: executionDays[dayIndex].tasks,
            change: .move(
                taskID: taskID,
                proposedStart: currentTime,
                minimumMovableStart: minimumMovableStart(for: dayID)
            ),
            dayStart: calendar.startOfDay(for: dayID),
            calendar: calendar
        )
        executionDays[dayIndex].tasks = reflowed
    }

    @MainActor
    func rescheduleExecutionTaskLater(dayID: Date, taskID: UUID, delayMinutes: Int = 15) {
        let proposedStart = calendar.date(
            byAdding: .minute,
            value: max(delayMinutes, 5),
            to: currentTime
        ) ?? currentTime
        moveExecutionTask(dayID: dayID, taskID: taskID, startDate: proposedStart)
    }

    /// Reorder tasks belonging to a single source block. Delegates to the reflow
    /// so AI variants can override (e.g. re-optimize the whole block on reorder).
    @MainActor
    func reorderExecutionTasks(dayID: Date, sourceBlockID: UUID, orderedTaskIDs: [UUID]) {
        guard let dayIndex = executionDays.firstIndex(where: { $0.id == dayID }) else { return }
        let dayStart = calendar.startOfDay(for: dayID)
        let reflowed = executionReflow.reflow(
            tasks: executionDays[dayIndex].tasks,
            change: .reorderWithinBlock(sourceBlockID: sourceBlockID, orderedTaskIDs: orderedTaskIDs),
            dayStart: dayStart,
            calendar: calendar
        )
        executionDays[dayIndex].tasks = reflowed
    }

    func areAllTasksCompleted(in blockID: UUID) -> Bool {
        guard let block = blocks.first(where: { $0.id == blockID }) else { return false }
        guard !block.tasks.isEmpty else { return false }
        return block.tasks.allSatisfy(\.isCompleted)
    }

    // MARK: - Planning

    private func snapshotTimelessNominals() {
        timelessNominalMinutesByBlockID.removeAll(keepingCapacity: true)
        for block in blocks {
            timelessNominalMinutesByBlockID[block.id] = max(block.durationMinutes, 1)
        }
    }

    private func snapshotFormulaNominals(adjustForPriority: Bool = false) {
        formulaNominalMinutesByBlockID.removeAll(keepingCapacity: true)
        for block in blocks {
            var minutes = max(block.durationMinutes, 1)
            if adjustForPriority, block.taskSource == .executionFill {
                let openTasks = block.tasks.filter { !$0.isCompleted }
                let primaryCount = openTasks.filter(\.isPrimary).count
                let taskPressure = min(openTasks.count * 3, 18)
                let priorityPressure = min(primaryCount * 12, 36)
                minutes += taskPressure + priorityPressure
            }
            formulaNominalMinutesByBlockID[block.id] = minutes
        }
    }

    private func applyTimelessPlan(
        plannedBlockIndices: [Int],
        runStart: Date,
        targetEnd: Date
    ) {
        let context = DayRunPlanContext(
            blocks: blocks,
            plannedBlockIndices: plannedBlockIndices,
            runStart: runStart,
            targetEnd: targetEnd,
            nominalMinutesByBlockID: timelessNominalMinutesByBlockID,
            planningSource: .formulaProportionalWindow
        )

        do {
            let result = try dayRunPlanner.makePlan(context: context)
            blocks = result.blocks
            lastDayRunPlanMetadata = result.metadata
        } catch {
            chainPlannedBlocksFromNominals(
                plannedBlockIndices: plannedBlockIndices,
                startingAt: runStart,
                nominalMinutesByBlockID: timelessNominalMinutesByBlockID
            )
        }
    }

    private func applyFormulaPlan(
        plannedBlockIndices: [Int],
        runStart: Date,
        targetEnd: Date
    ) {
        let context = DayRunPlanContext(
            blocks: blocks,
            plannedBlockIndices: plannedBlockIndices,
            runStart: runStart,
            targetEnd: targetEnd,
            nominalMinutesByBlockID: formulaPlanningNominalMinutesByBlockID(),
            planningSource: .formulaProportionalWindow
        )

        do {
            let result = try dayRunPlanner.makePlan(context: context)
            blocks = result.blocks
            lastDayRunPlanMetadata = result.metadata
        } catch {
            chainPlannedBlocksFromNominals(
                plannedBlockIndices: plannedBlockIndices,
                startingAt: runStart,
                nominalMinutesByBlockID: formulaPlanningNominalMinutesByBlockID()
            )
        }
    }

    private func formulaPlanningNominalMinutesByBlockID() -> [UUID: Int] {
        guard TodayDisplayPreferences.priorityWeightedRebalancePreference() else {
            return formulaNominalMinutesByBlockID
        }

        var weighted = formulaNominalMinutesByBlockID
        for block in blocks {
            let base = Double(formulaNominalMinutesByBlockID[block.id] ?? max(block.durationMinutes, 1))
            if block.locksPlannedDuration {
                weighted[block.id] = max(1, Int(base.rounded()))
                continue
            }
            let typeWeight: Double
            if let p = block.schedulingPriority {
                typeWeight = Double(p) / 50.0
            } else {
                switch block.type {
                case .focus: typeWeight = 1.35
                case .fixed: typeWeight = 1.20
                case .routine: typeWeight = 1.0
                case .mini: typeWeight = 0.75
                }
            }
            let primaryBoost = block.tasks.contains(where: \.isPrimary) ? 1.18 : 1.0
            weighted[block.id] = max(1, Int((base * typeWeight * primaryBoost).rounded()))
        }
        return weighted
    }

    private func effectiveFormulaTargetEnd(from runStart: Date, redistributingEarlyFinish: Bool = false) -> Date? {
        if redistributingEarlyFinish,
           !TodayDisplayPreferences.redistributeEarlyFinishPreference() {
            return nil
        }

        guard TodayDisplayPreferences.glueToFinishTimePreference() else { return nil }
        guard let targetEnd = formulaTargetDayEnd, targetEnd > runStart else { return nil }
        return targetEnd
    }

    private func chainPlannedBlocksFromNominals(
        plannedBlockIndices: [Int],
        startingAt runStart: Date,
        nominalMinutesByBlockID: [UUID: Int]
    ) {
        var cursor = runStart
        for index in plannedBlockIndices {
            let minutes = nominalMinutesByBlockID[blocks[index].id] ?? max(blocks[index].durationMinutes, 1)
            blocks[index].startTime = cursor
            blocks[index].endTime = calendar.date(byAdding: .minute, value: minutes, to: cursor) ?? cursor
            cursor = blocks[index].endTime
        }
    }

    private func reflowFormulaBlocksAroundFixedTimes(
        plannedBlockIndices: [Int],
        runStart: Date,
        targetEnd: Date?
    ) {
        guard !plannedBlockIndices.isEmpty else { return }

        let validIndices = plannedBlockIndices.filter { blocks.indices.contains($0) }
        guard !validIndices.isEmpty else { return }

        var cursor = runStart
        var flexibleSegment: [Int] = []

        for index in validIndices {
            if isFixedTimeScheduleBlock(blocks[index]) {
                if blocks[index].startTime > cursor, !flexibleSegment.isEmpty {
                    planFormulaFlexibleSegment(
                        flexibleSegment,
                        runStart: cursor,
                        targetEnd: blocks[index].startTime
                    )
                    flexibleSegment.removeAll()
                }

                if blocks[index].endTime > cursor {
                    cursor = blocks[index].endTime
                }
            } else {
                flexibleSegment.append(index)
            }
        }

        planFormulaFlexibleSegment(
            flexibleSegment,
            runStart: cursor,
            targetEnd: targetEnd
        )
    }

    private func planFormulaFlexibleSegment(
        _ plannedBlockIndices: [Int],
        runStart: Date,
        targetEnd: Date?
    ) {
        guard !plannedBlockIndices.isEmpty else { return }

        if let targetEnd, targetEnd > runStart {
            applyFormulaPlan(
                plannedBlockIndices: plannedBlockIndices,
                runStart: runStart,
                targetEnd: targetEnd
            )
        } else {
            chainPlannedBlocksFromNominals(
                plannedBlockIndices: plannedBlockIndices,
                startingAt: runStart,
                nominalMinutesByBlockID: formulaNominalMinutesByBlockID
            )
        }
    }

    private func isFixedTimeScheduleBlock(_ block: DayBlock) -> Bool {
        block.pinsToClock || block.isAnchorBlock
    }

    /// True when this block is tied to an explicit clock time in the schedule list (not gated on “protect fixed” reflow prefs).
    private func isClockAnchoredForOrdering(_ block: DayBlock) -> Bool {
        block.pinsToClock || block.isAnchorBlock
    }

    /// When walking the list in order, fixed / anchor blocks must have non-decreasing `startTime`.
    private func clockAnchoredFixedTimeOrderViolation(in orderedBlocks: [DayBlock])
        -> (laterListedFirst: DayBlock, earlierListedSecond: DayBlock)? {
        var previousClockAnchored: DayBlock?
        for block in orderedBlocks {
            guard isClockAnchoredForOrdering(block) else { continue }
            if let prev = previousClockAnchored, block.startTime < prev.startTime {
                return (prev, block)
            }
            previousClockAnchored = block
        }
        return nil
    }

    /// Counts pairwise inversions among clock-anchored blocks.
    /// `0` means the anchored sequence is chronologically ordered.
    private func clockAnchoredFixedTimeInversionCount(in orderedBlocks: [DayBlock]) -> Int {
        let anchored = orderedBlocks.filter(isClockAnchoredForOrdering)
        guard anchored.count > 1 else { return 0 }

        var inversions = 0
        for earlierIndex in anchored.indices {
            let earlier = anchored[earlierIndex]
            for laterIndex in anchored.indices where laterIndex > earlierIndex {
                if anchored[laterIndex].startTime < earlier.startTime {
                    inversions += 1
                }
            }
        }
        return inversions
    }

    private func showClockAnchoredFixedTimeOrderViolationToast(
        laterListedFirst: DayBlock,
        earlierListedSecond: DayBlock
    ) {
        let lateLabel = CueInTimeFormat.hourMinute(laterListedFirst.startTime)
        let earlyLabel = CueInTimeFormat.hourMinute(earlierListedSecond.startTime)
        CueInToastCenter.shared.showWarning(
            icon: "clock.badge.exclamationmark",
            title: "Fixed times out of order",
            message: "“\(laterListedFirst.title)” (\(lateLabel)) is above “\(earlierListedSecond.title)” (\(earlyLabel)) in the layout. Earlier fixed times must come first."
        )
    }

    private func rescheduleStoppedFormulaAfterReorder() {
        guard let stoppedAt = formulaStoppedAt else { return }

        let movableIndices = blocks.indices.filter { index in
            blocks[index].state == .active || blocks[index].state == .upcoming
        }
        guard let firstIndex = movableIndices.first else { return }

        for index in movableIndices {
            blocks[index].state = index == firstIndex ? .active : .upcoming
        }

        reflowFormulaBlocksAroundFixedTimes(
            plannedBlockIndices: Array(movableIndices),
            runStart: stoppedAt,
            targetEnd: effectiveFormulaTargetEnd(from: stoppedAt)
        )
    }

    // MARK: - Schedule ↔ Timeline bridging
    //
    // The Schedule (formula mode) and the Timeline (task-led mode) are two views
    // of the same day. When a Schedule run goes live:
    //
    //   1. Every **template-task block** (routines, fixed blocks with explicit
    //      tasks) is mirrored to the Timeline as a single anchored card that
    //      occupies the block's window. The user sees their routines on the
    //      clock surface without having to switch tabs.
    //
    //   2. Every **timeline anchor** (a pool task whose block type is `.fixed`)
    //      is mirrored back into the Schedule as a `.fixed` DayBlock pinned
    //      at the anchor's start time. The schedule deal becomes aware of
    //      meetings / appointments already pinned in the day.
    //
    // Both projections are disposable: stopping / resetting the schedule
    // removes them and restores the surfaces to their stand-alone state.

    /// IDs of timeline cards that are represented as their own `.fixed` blocks
    /// in the live schedule. Used when filling execution blocks so anchor
    /// tasks aren't double-pulled.
    private var anchorClaimedCardIDs: Set<UUID> = []

    /// Project every *template-task* schedule block onto today's Timeline as an
    /// anchored card. Idempotent: updates an existing projection in place when
    /// the backing block's time / state / tasks change; adds or removes cards
    /// only when the block membership itself shifts. Safe to call from tick.
    @MainActor
    private func injectScheduleBlocksIntoTimeline() {
        guard let dayIndex = todayExecutionDayIndex else { return }

        let injectable = blocks.filter { block in
            block.taskSource == .templateTasks && !block.isAnchorBlock
        }
        let injectableIDs = Set(injectable.map(\.id))

        executionDays[dayIndex].tasks.removeAll { task in
            guard let blockID = task.scheduleInjectedBlockID else { return false }
            return !injectableIDs.contains(blockID)
        }

        var indexByBlockID: [UUID: Int] = [:]
        for (index, task) in executionDays[dayIndex].tasks.enumerated() {
            if let blockID = task.scheduleInjectedBlockID {
                indexByBlockID[blockID] = index
            }
        }

        for block in injectable {
            if let index = indexByBlockID[block.id] {
                updateInjectedCardInPlace(&executionDays[dayIndex].tasks[index], for: block)
            } else {
                executionDays[dayIndex].tasks.append(makeScheduleInjectedCard(for: block))
            }
        }

        executionDays[dayIndex].tasks.sort { $0.startDate < $1.startDate }
    }

    /// Apply the block's latest fields onto an already-injected card without
    /// changing the card id — so UI identities / gesture state stay stable.
    private func updateInjectedCardInPlace(_ card: inout ExecutionTaskCard, for block: DayBlock) {
        let refreshed = makeScheduleInjectedCard(for: block)
        card.title = refreshed.title
        card.blockTitle = refreshed.blockTitle
        card.blockTypeLabel = refreshed.blockTypeLabel
        card.blockType = refreshed.blockType
        card.startDate = refreshed.startDate
        card.durationMinutes = refreshed.durationMinutes
        card.isCompleted = refreshed.isCompleted
        card.isPrimary = refreshed.isPrimary
        card.isRepeating = refreshed.isRepeating
        card.lane = refreshed.lane
        card.pinsToClock = refreshed.pinsToClock
        card.timelineAccentHex = refreshed.timelineAccentHex
    }

    private func updateAnchorExecutionCard(from block: DayBlock) {
        guard let cardID = block.anchorExecutionCardID else { return }

        for dayIndex in executionDays.indices {
            guard let cardIndex = executionDays[dayIndex].tasks.firstIndex(where: { $0.id == cardID }) else {
                continue
            }

            executionDays[dayIndex].tasks[cardIndex].title = block.title
            executionDays[dayIndex].tasks[cardIndex].blockTitle = "Fixed time"
            executionDays[dayIndex].tasks[cardIndex].blockTypeLabel = block.type.label
            executionDays[dayIndex].tasks[cardIndex].blockType = block.type
            executionDays[dayIndex].tasks[cardIndex].startDate = block.startTime
            executionDays[dayIndex].tasks[cardIndex].durationMinutes = max(block.durationMinutes, 1)
            executionDays[dayIndex].tasks[cardIndex].lane = ExecutionLane.suggested(for: block.type)
            executionDays[dayIndex].tasks[cardIndex].pinsToClock = block.pinsToClock
            executionDays[dayIndex].tasks[cardIndex].timelineAccentHex = block.timelineAccentHex
            executionDays[dayIndex].tasks[cardIndex].isPrimary = block.tasks.contains(where: \.isPrimary)
            executionDays[dayIndex].tasks[cardIndex].isRepeating = block.isRepeatable

            if let plannerID = executionDays[dayIndex].tasks[cardIndex].plannerTaskItemID {
                updatePlannerTask(from: executionDays[dayIndex].tasks[cardIndex], plannerID: plannerID)
            }
        }
    }

    private func removeAnchorExecutionCardIfNeeded(for block: DayBlock) {
        guard let cardID = block.anchorExecutionCardID else { return }
        anchorClaimedCardIDs.remove(cardID)

        for dayIndex in executionDays.indices {
            if let card = executionDays[dayIndex].tasks.first(where: { $0.id == cardID }),
               let plannerID = card.plannerTaskItemID {
                TasksStore.shared.deleteTask(plannerID)
            }
            executionDays[dayIndex].tasks.removeAll { $0.id == cardID }
        }
    }

    @MainActor
    private func removeScheduleInjectionsFromTimeline() {
        guard let dayIndex = todayExecutionDayIndex else { return }
        removeScheduleInjectionsFromTimeline(dayIndex: dayIndex)
    }

    @MainActor
    private func removeScheduleInjectionsFromTimeline(dayIndex: Int) {
        executionDays[dayIndex].tasks.removeAll(where: \.isScheduleInjected)
    }

    private func makeScheduleInjectedCard(for block: DayBlock) -> ExecutionTaskCard {
        let openTasks = block.tasks.filter { !$0.isCompleted }.count
        let totalTasks = block.tasks.count
        let subtitle: String
        switch totalTasks {
        case 0:   subtitle = block.type.label
        case 1:   subtitle = block.tasks.first?.title ?? block.type.label
        default:
            let done = totalTasks - openTasks
            subtitle = done > 0
                ? "\(totalTasks) tasks · \(done) done"
                : "\(totalTasks) tasks"
        }

        let isAllDone = totalTasks > 0 && openTasks == 0
        let duration = max(block.durationMinutes, 1)

        return ExecutionTaskCard(
            id: UUID(),
            sourceBlockID: block.id,
            sourceTaskID: nil,
            title: block.title,
            blockTitle: subtitle,
            blockTypeLabel: block.type.label,
            blockType: block.type,
            startDate: block.startTime,
            durationMinutes: duration,
            lane: ExecutionLane.suggested(for: block.type),
            isCompleted: isAllDone,
            isRepeating: block.isRepeatable,
            isPrimary: block.tasks.contains { $0.isPrimary },
            field: nil,
            project: nil,
            folder: nil,
            plannerTaskItemID: nil,
            scheduleInjectedBlockID: block.id,
            pinsToClock: block.pinsToClock,
            timelineAccentHex: block.timelineAccentHex
        )
    }

    /// Collect timeline cards that act as immovable anchors for the day.
    @MainActor
    private func collectTimelineAnchorsAsScheduleBlocks() -> [DayBlock] {
        guard let dayIndex = todayExecutionDayIndex else { return [] }

        return executionDays[dayIndex].tasks.compactMap { card -> DayBlock? in
            guard card.pinsToClock, !card.isScheduleInjected else { return nil }
            guard !card.isCompleted else { return nil }

            return DayBlock(
                title: card.title,
                type: card.blockType,
                state: .upcoming,
                startTime: card.startDate,
                endTime: card.endDate,
                flowMode: .flowing,
                taskSource: .templateTasks,
                tasks: [
                    DayTask(
                        id: card.sourceTaskID ?? card.id,
                        title: card.title,
                        isCompleted: card.isCompleted,
                        isPrimary: card.isPrimary,
                        isRepeating: card.isRepeating,
                        sourceExecutionBlockID: card.sourceBlockID,
                        sourceExecutionTaskID: card.id,
                        field: card.field,
                        project: card.project,
                        folder: card.folder
                    )
                ],
                isRepeatable: false,
                pinsToClock: true,
                timelineAccentHex: card.timelineAccentHex,
                anchorExecutionCardID: card.id
            )
        }
    }

    /// Insert anchor blocks into the scheduled `blocks`, sorted by time.
    private func mergeAnchorBlocksIntoSchedule(_ anchors: [DayBlock]) {
        blocks.removeAll { $0.isAnchorBlock }
        guard !anchors.isEmpty else { return }
        blocks.append(contentsOf: anchors)
        blocks.sort { $0.startTime < $1.startTime }
    }

    private var todayExecutionDayIndex: Int? {
        executionDays.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: currentTime) })
    }

    private func rescheduleTailAfterCompletion(completedIndex: Int, from now: Date) {
        let startIndex = completedIndex + 1
        guard startIndex < blocks.count else { return }

        if dayEngineMode == .formulaBased {
            let tail = blocks.indices.filter { index in
                index >= startIndex
                    && blocks[index].state != .skipped
                    && blocks[index].state != .completed
            }
            reflowFormulaBlocksAroundFixedTimes(
                plannedBlockIndices: Array(tail),
                runStart: now,
                targetEnd: effectiveFormulaTargetEnd(from: now, redistributingEarlyFinish: true)
            )
            return
        }

        var cursor = now
        for index in startIndex..<blocks.count {
            if blocks[index].state == .skipped || blocks[index].state == .completed { continue }
            let durationMinutes = max(blocks[index].durationMinutes, 1)
            blocks[index].startTime = cursor
            blocks[index].endTime = calendar.date(byAdding: .minute, value: durationMinutes, to: cursor) ?? cursor
            cursor = blocks[index].endTime
        }
    }

    private func rescheduleFormulaAfterReorder() {
        guard isFormulaRunLive else { return }

        let tail = blocks.indices.filter { blocks[$0].state == .upcoming }
        guard !tail.isEmpty else { return }

        let runStart = max(currentBlock?.endTime ?? currentTime, currentTime)
        reflowFormulaBlocksAroundFixedTimes(
            plannedBlockIndices: Array(tail),
            runStart: runStart,
            targetEnd: effectiveFormulaTargetEnd(from: runStart)
        )
    }

    private func restartLiveFormulaFlowFromCurrentOrder() {
        guard isFormulaRunLive else { return }

        let now = Date()
        currentTime = now

        guard let activeIndex = blocks.firstIndex(where: { block in
            block.state != .completed && block.state != .skipped
        }) else {
            removeScheduleInjectionsFromTimeline()
            return
        }

        for index in blocks.indices {
            if blocks[index].state == .completed || blocks[index].state == .skipped { continue }
            blocks[index].state = index == activeIndex ? .active : .upcoming
        }

        let remaining = blocks.indices.filter { index in
            index >= activeIndex
                && blocks[index].state != .completed
                && blocks[index].state != .skipped
        }

        reflowFormulaBlocksAroundFixedTimes(
            plannedBlockIndices: Array(remaining),
            runStart: now,
            targetEnd: effectiveFormulaTargetEnd(from: now)
        )

        injectScheduleBlocksIntoTimeline()
    }

    private func recalibrateOverdueBlockingFormulaRun() {
        // Legacy path collapsed overdue blocking `endTime` to “now” and reflowed the tail, which destroyed the
        // planned slice duration on cards and compressed later blocks. Overdue blocking runs until Done; no auto-shrink.
    }

    private func restartLiveTimelessFlowFromCurrentOrder() {
        guard isTimelessRunLive, let dayEnd = timelessTargetDayEnd else { return }

        let now = Date()
        currentTime = now

        guard let activeIndex = blocks.firstIndex(where: { block in
            block.state != .completed && block.state != .skipped
        }) else {
            return
        }

        for index in blocks.indices {
            if blocks[index].state == .completed || blocks[index].state == .skipped { continue }
            blocks[index].state = index == activeIndex ? .active : .upcoming
        }

        let activeMinutes = timelessNominalMinutesByBlockID[blocks[activeIndex].id]
            ?? max(blocks[activeIndex].durationMinutes, 1)
        blocks[activeIndex].startTime = now
        blocks[activeIndex].endTime = calendar.date(
            byAdding: .minute,
            value: max(activeMinutes, 1),
            to: now
        ) ?? now

        let tail = blocks.indices.filter { index in
            index > activeIndex && blocks[index].state == .upcoming
        }
        guard !tail.isEmpty else { return }

        applyTimelessPlan(
            plannedBlockIndices: Array(tail),
            runStart: blocks[activeIndex].endTime,
            targetEnd: dayEnd
        )
    }

    @MainActor
    private func sealLiveProgressiveAdvanceAfterManualBlockComplete() {
        let now = Date()
        currentTime = now
        deriveBlockStates()

        guard currentBlock == nil, remainingBlockCount > 0 else { return }
        guard let head = blocks.firstIndex(where: { $0.state != .completed && $0.state != .skipped }) else {
            return
        }
        guard !isFixedTimeScheduleBlock(blocks[head]) else { return }

        if isFormulaRunLive {
            restartLiveFormulaFlowFromCurrentOrder()
            currentTime = Date()
            deriveBlockStates()
        } else if isTimelessRunLive {
            restartLiveTimelessFlowFromCurrentOrder()
            currentTime = Date()
            deriveBlockStates()
        }
    }

    // MARK: - Private Helpers

    @MainActor
    private func syncExecutionPoolFromTasksStore() {
        if executionDays.isEmpty {
            executionDays = Self.makeEmptyExecutionDays(relativeTo: currentTime)
        }

        let todayStart = calendar.startOfDay(for: currentTime)
        guard let dayIndex = executionDays.firstIndex(where: { calendar.isDate($0.id, inSameDayAs: todayStart) }) else {
            executionDays = Self.makeEmptyExecutionDays(relativeTo: currentTime)
            guard let refreshedIndex = executionDays.firstIndex(where: { calendar.isDate($0.id, inSameDayAs: todayStart) }) else { return }
            syncExecutionPoolFromTasksStore(dayIndex: refreshedIndex, todayStart: todayStart)
            return
        }

        syncExecutionPoolFromTasksStore(dayIndex: dayIndex, todayStart: todayStart)
    }

    private func syncExecutionPoolFromTasksStore(dayIndex: Int, todayStart: Date) {
        let pool = TasksStore.shared.todayTasks
        let poolIDs = Set(pool.map(\.id))
        var existingPlannerIDs = Set<UUID>()

        executionDays[dayIndex].tasks.removeAll { task in
            // Preserve cards projected from the live Schedule (Routine / Fixed blocks shown on the Timeline).
            if task.isScheduleInjected { return false }
            // Stale planner rows: drop if the task is no longer queued for today.
            if let plannerID = task.plannerTaskItemID {
                return !poolIDs.contains(plannerID)
            }
            // Legacy execution-only rows without a backing task: clear them during a resync.
            return true
        }

        for taskIndex in executionDays[dayIndex].tasks.indices {
            guard
                let plannerID = executionDays[dayIndex].tasks[taskIndex].plannerTaskItemID,
                let item = pool.first(where: { $0.id == plannerID })
            else {
                continue
            }
            existingPlannerIDs.insert(plannerID)
            refreshExecutionCard(&executionDays[dayIndex].tasks[taskIndex], from: item)
        }

        var cursor = max(
            executionDays[dayIndex].tasks.map(\.endDate).max() ?? todayStart,
            currentTime
        )
        for item in pool where !existingPlannerIDs.contains(item.id) {
            let card = makeExecutionCard(from: item, start: cursor)
            executionDays[dayIndex].tasks.append(card)
            cursor = card.endDate
        }

        executionDays[dayIndex].tasks.sort { $0.startDate < $1.startDate }
    }

    private func refreshExecutionCard(_ card: inout ExecutionTaskCard, from item: TaskItem) {
        let store = TasksStore.shared
        let blockType = blockType(for: item)
        card.title = item.title
        card.blockTitle = "Tasks"
        card.blockTypeLabel = "Queued"
        card.blockType = blockType
        card.durationMinutes = max(min(item.plannedMinutes, 8 * 60), 5)
        card.lane = ExecutionLane.suggested(for: blockType)
        card.isCompleted = item.isCompleted
        card.isRepeating = item.recurrence != .none
        card.isPrimary = item.priority == .urgent || item.priority == .high
        card.field = item.fieldID.flatMap { store.field($0)?.name }
        card.project = item.projectID.flatMap { store.project($0)?.name }
        card.folder = nil
    }

    private func makeExecutionCard(from item: TaskItem, start: Date) -> ExecutionTaskCard {
        let store = TasksStore.shared
        let blockType = blockType(for: item)
        return ExecutionTaskCard(
            id: UUID(),
            sourceBlockID: nil,
            sourceTaskID: nil,
            title: item.title,
            blockTitle: "Tasks",
            blockTypeLabel: "Queued",
            blockType: blockType,
            startDate: start,
            durationMinutes: max(min(item.plannedMinutes, 8 * 60), 5),
            lane: ExecutionLane.suggested(for: blockType),
            isCompleted: item.isCompleted,
            isRepeating: item.recurrence != .none,
            isPrimary: item.priority == .urgent || item.priority == .high,
            field: item.fieldID.flatMap { store.field($0)?.name },
            project: item.projectID.flatMap { store.project($0)?.name },
            folder: nil,
            plannerTaskItemID: item.id,
            pinsToClock: false
        )
    }

    private func blockType(for item: TaskItem) -> BlockType {
        switch item.executionType {
        case .deepWork: return .focus
        case .shallowWork: return .mini
        case .multitask: return .mini
        case nil: return .mini
        }
    }

    @MainActor
    private func loadTaskLeadDay(reset: Bool) {
        if reset || taskLeadBlocks.isEmpty {
            taskLeadBlocks = Self.taskLedBlocksForDemoPreference()
            clearTimelessRuntime()
        } else if executionDays.isEmpty {
            executionDays = Self.makeEmptyExecutionDays(relativeTo: currentTime)
        }
        syncExecutionPoolFromTasksStore()
        blocks = taskLeadBlocks
        deriveBlockStates()
    }

    /// Task-led sample blocks from ``MockDataService``, unless demo data was removed (empty day).
    private static func taskLedBlocksForDemoPreference() -> [DayBlock] {
        if UserDefaults.standard.bool(forKey: CueInAppDataKeys.gimmickDemoRemoved) {
            return []
        }
        return MockDataService.sampleDay()
    }

    /// Reloads bundled + UserDefaults-backed formulas after library edits.
    @MainActor
    func reloadAvailableFormulasFromLibrary() {
        availableFormulas = FormulaLibraryService.allSchedules
        if let sid = selectedFormulaID,
           availableFormulas.contains(where: { $0.id == sid }) {
            Self.persistFormulaSelection(selectedFormulaID)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.persistedFormulaSelectionKey)
            selectedFormulaID = Self.loadPersistedFormulaSelection(availableFormulas: availableFormulas)
            Self.persistFormulaSelection(selectedFormulaID)
        }
        if dayEngineMode == .formulaBased {
            prepareFormulaPreview()
        }
        deriveBlockStates()
    }

    /// Clears persisted schedule snapshot, formula run timers, and resets visible blocks (preserves ``dayEngineMode``).
    @MainActor
    func resetSchedulePersistenceAndBlocks(useGimmickTaskLedSample: Bool) {
        removeScheduleInjectionsFromTimeline()
        anchorClaimedCardIDs.removeAll(keepingCapacity: true)
        clearPersistedFormulaRuntimeState()
        formulaRunStartedAt = nil
        formulaStoppedAt = nil
        formulaSchedulePausedAt = nil
        formulaTargetDayEnd = nil
        formulaNominalMinutesByBlockID.removeAll()
        futurePinnedFormulaBlocks.removeAll()
        isExecutionPaused = false
        executionPausedAt = nil
        lastDayRunPlanMetadata = nil
        executionDays = Self.makeEmptyExecutionDays(relativeTo: currentTime)

        UserDefaults.standard.removeObject(forKey: Self.persistedFormulaSelectionKey)
        availableFormulas = FormulaLibraryService.allSchedules
        selectedFormulaID = Self.loadPersistedFormulaSelection(availableFormulas: availableFormulas)
        Self.persistFormulaSelection(selectedFormulaID)

        clearTimelessRuntime()

        if dayEngineMode == .taskLed {
            taskLeadBlocks = useGimmickTaskLedSample ? MockDataService.sampleDay() : []
            blocks = taskLeadBlocks
        } else {
            formulaBlocks = []
            prepareFormulaPreview()
        }
        syncExecutionPoolFromTasksStore()
        deriveBlockStates()
    }

    /// Fresh-install defaults for Today after wiping ``UserDefaults``.
    @MainActor
    func performFreshInstallReset() {
        UserDefaults.standard.removeObject(forKey: Self.persistedScheduleRunKey)
        UserDefaults.standard.removeObject(forKey: Self.persistedFormulaSelectionKey)
        lastPersistedScheduleData = nil
        availableFormulas = FormulaLibraryService.allSchedules
        dayEngineMode = .taskLed
        UserDefaults.standard.set(DayEngineMode.taskLed.rawValue, forKey: DayEngineMode.storageKey)
        selectedFormulaID = Self.loadPersistedFormulaSelection(availableFormulas: availableFormulas)
        Self.persistFormulaSelection(selectedFormulaID)
        resetSchedulePersistenceAndBlocks(useGimmickTaskLedSample: true)
    }

    @MainActor
    private func prepareFormulaPreview(anchor: Date = Date()) {
        formulaSchedulePausedAt = nil
        guard let formula = selectedFormula else {
            blocks = []
            formulaBlocks = []
            formulaRunStartedAt = nil
            formulaStoppedAt = nil
            formulaTargetDayEnd = nil
            formulaNominalMinutesByBlockID.removeAll(keepingCapacity: true)
            deriveBlockStates()
            resetFormulaPreviewStructureChangeTrackingToClean()
            return
        }

        blocks = materializedFormulaBlocks(formula: formula, anchor: anchor, fillsFromExecution: false)
        snapshotFormulaNominals()
        formulaRunStartedAt = nil
        formulaStoppedAt = nil
        formulaTargetDayEnd = nil
        deriveBlockStates()
        resetFormulaPreviewStructureChangeTrackingToClean()
    }

    @MainActor
    private func finishFormulaBlock() {
        guard formulaRunStartedAt != nil else { return }
        guard let index = blocks.firstIndex(where: { $0.state == .active }) else { return }
        let now = Date()
        currentTime = now
        if let pausedAt = formulaSchedulePausedAt {
            formulaSchedulePausedAt = nil
            shiftFormulaScheduleAfterElapsedPause(pausedAt: pausedAt, resumeNow: now)
            if !TodayDisplayPreferences.pullsTasksFromExecutionPoolPreference() {
                clearExecutionFillAssignmentsFromSchedule()
            }
        }
        markBlockTasksCompleted(at: index)
        blocks[index].state = .completed

        let tail = blocks.indices.filter { indexToCheck in
            indexToCheck > index && blocks[indexToCheck].state != .skipped && blocks[indexToCheck].state != .completed
        }
        if let dayEnd = formulaTargetDayEnd, !tail.isEmpty, now < dayEnd {
            reflowFormulaBlocksAroundFixedTimes(
                plannedBlockIndices: Array(tail),
                runStart: now,
                targetEnd: effectiveFormulaTargetEnd(from: now, redistributingEarlyFinish: true)
            )
        } else {
            rescheduleTailAfterCompletion(completedIndex: index, from: now)
        }
        sealLiveProgressiveAdvanceAfterManualBlockComplete()
    }

    private func clearTimelessRuntime() {
        timelessRunStartedAt = nil
        timelessTargetDayEnd = nil
        timelessNominalMinutesByBlockID.removeAll()
        lastDayRunPlanMetadata = nil
    }

    @MainActor
    private func restoreFormulaPreviewAfterUnstartedStop() {
        formulaSchedulePausedAt = nil
        formulaRunStartedAt = nil
        formulaStoppedAt = nil
        formulaTargetDayEnd = nil
        formulaNominalMinutesByBlockID.removeAll(keepingCapacity: true)
        clearPersistedFormulaRuntimeState()

        if selectedFormulaID != nil {
            prepareFormulaPreview(anchor: currentTime)
        } else {
            for index in blocks.indices where blocks[index].state != .skipped {
                blocks[index].state = .upcoming
            }
            formulaBlocks = blocks
            deriveBlockStates()
        }
    }

    @MainActor
    @discardableResult
    private func normalizeUnstartedStoppedFormulaRunIfNeeded() -> Bool {
        guard formulaStoppedAt != nil, !hasMeaningfulStoppedFormulaRun else { return false }
        restoreFormulaPreviewAfterUnstartedStop()
        return true
    }

    private func markBlockTasksCompleted(at index: Int) {
        guard blocks.indices.contains(index) else { return }
        for taskIndex in blocks[index].tasks.indices {
            blocks[index].tasks[taskIndex].isCompleted = true
            syncExecutionTaskState(
                from: blocks[index].tasks[taskIndex],
                fallbackBlockID: blocks[index].id,
                fallbackTaskID: blocks[index].tasks[taskIndex].id,
                isCompleted: true
            )
        }
    }

    private func persistCurrentBlocks() {
        switch dayEngineMode {
        case .taskLed:
            taskLeadBlocks = blocks
        case .formulaBased:
            formulaBlocks = blocks
            persistFormulaRuntimeState()
        }
    }

    private func restoreFormulaRuntimeIfAvailable(now: Date) {
        guard
            let data = UserDefaults.standard.data(forKey: Self.persistedScheduleRunKey),
            let state = try? JSONDecoder().decode(PersistedScheduleRunState.self, from: data)
        else {
            return
        }

        if let formulaID = state.selectedFormulaID,
           availableFormulas.contains(where: { $0.id == formulaID }) {
            selectedFormulaID = formulaID
        }

        formulaBlocks = state.blocks
        blocks = state.blocks
        futurePinnedFormulaBlocks = state.futurePinnedBlocks ?? []
        formulaRunStartedAt = state.formulaRunStartedAt
        formulaStoppedAt = state.formulaStoppedAt
        formulaSchedulePausedAt = state.formulaSchedulePausedAt
        formulaTargetDayEnd = state.formulaTargetDayEnd
        formulaNominalMinutesByBlockID = Dictionary(
            uniqueKeysWithValues: state.nominalMinutes.map { ($0.blockID, $0.minutes) }
        )
        currentTime = now
        if normalizeUnstartedStoppedFormulaRunIfNeeded() { return }
        deriveFormulaBlockStates()
        if !TodayDisplayPreferences.pullsTasksFromExecutionPoolPreference() {
            for i in blocks.indices where blocks[i].taskSource == .executionFill {
                blocks[i].tasks = []
            }
        }
        Self.persistFormulaSelection(selectedFormulaID)
        persistCurrentBlocks()
        if formulaRunStartedAt == nil, formulaStoppedAt == nil {
            resetFormulaPreviewStructureChangeTrackingToClean()
        }
    }

    private func persistFormulaRuntimeState() {
        guard dayEngineMode == .formulaBased else { return }

        if formulaRunStartedAt != nil || isFormulaRunStopped {
            let state = PersistedScheduleRunState(
                selectedFormulaID: selectedFormulaID,
                blocks: blocks,
                formulaRunStartedAt: formulaRunStartedAt,
                formulaStoppedAt: formulaStoppedAt,
                formulaSchedulePausedAt: formulaSchedulePausedAt,
                formulaTargetDayEnd: formulaTargetDayEnd,
                nominalMinutes: formulaNominalMinutesByBlockID.map {
                    PersistedScheduleNominalMinutes(blockID: $0.key, minutes: $0.value)
                },
                futurePinnedBlocks: futurePinnedFormulaBlocks,
                savedAt: Date()
            )

            guard let data = try? JSONEncoder().encode(state) else { return }
            if data == lastPersistedScheduleData { return }
            lastPersistedScheduleData = data
            UserDefaults.standard.set(data, forKey: Self.persistedScheduleRunKey)
            return
        }

        // Preview / unstarted schedule: persist so force-quitting before Start doesn’t discard edits.
        let hasPreviewWork = selectedFormulaID != nil || !blocks.isEmpty
        guard hasPreviewWork else {
            clearPersistedFormulaRuntimeState()
            return
        }

        let previewState = PersistedScheduleRunState(
            selectedFormulaID: selectedFormulaID,
            blocks: blocks,
            formulaRunStartedAt: nil,
            formulaStoppedAt: nil,
            formulaSchedulePausedAt: nil,
            formulaTargetDayEnd: nil,
            nominalMinutes: formulaNominalMinutesByBlockID.map {
                PersistedScheduleNominalMinutes(blockID: $0.key, minutes: $0.value)
            },
            futurePinnedBlocks: futurePinnedFormulaBlocks,
            savedAt: Date()
        )

        guard let data = try? JSONEncoder().encode(previewState) else { return }
        if data == lastPersistedScheduleData { return }
        lastPersistedScheduleData = data
        UserDefaults.standard.set(data, forKey: Self.persistedScheduleRunKey)
    }

    private func clearPersistedFormulaRuntimeState() {
        lastPersistedScheduleData = nil
        UserDefaults.standard.removeObject(forKey: Self.persistedScheduleRunKey)
    }

    private var flatTaskLeadItems: [TaskLeadTaskItem] {
        blocks.enumerated().flatMap { blockOffset, block in
            block.tasks.enumerated().map { taskOffset, task in
                TaskLeadTaskItem(
                    id: task.id,
                    blockID: block.id,
                    blockTitle: block.title,
                    blockTypeLabel: block.type.label,
                    blockState: block.state,
                    task: task,
                    order: (blockOffset * 100) + taskOffset
                )
            }
        }
        .sorted { $0.order < $1.order }
    }

    private func appendTaskLeadSection(
        id: String,
        title: String,
        subtitle: String?,
        items: [TaskLeadTaskItem],
        usedTaskIDs: inout Set<UUID>,
        into sections: inout [TaskLeadTaskSection]
    ) {
        guard !items.isEmpty else { return }
        sections.append(
            TaskLeadTaskSection(
                id: id,
                title: title,
                subtitle: subtitle,
                items: items
            )
        )
        for item in items {
            usedTaskIDs.insert(item.id)
        }
    }

    private static func restoredDayEngineMode() -> DayEngineMode {
        guard
            let rawValue = UserDefaults.standard.string(forKey: DayEngineMode.storageKey),
            let mode = DayEngineMode(rawValue: rawValue)
        else {
            return .taskLed
        }
        return mode
    }

    private func syncExecutionTaskState(
        from task: DayTask,
        fallbackBlockID: UUID,
        fallbackTaskID: UUID,
        isCompleted: Bool
    ) {
        let sourceBlockID = task.sourceExecutionBlockID ?? fallbackBlockID
        let sourceTaskID = task.sourceExecutionTaskID ?? fallbackTaskID

        if let blockIndex = taskLeadBlocks.firstIndex(where: { $0.id == sourceBlockID }),
           let taskIndex = taskLeadBlocks[blockIndex].tasks.firstIndex(where: { $0.id == sourceTaskID }) {
            taskLeadBlocks[blockIndex].tasks[taskIndex].isCompleted = isCompleted
        }

        for dayIndex in executionDays.indices {
            guard let taskIndex = executionDays[dayIndex].tasks.firstIndex(where: {
                $0.sourceBlockID == sourceBlockID && $0.sourceTaskID == sourceTaskID
            }) else {
                continue
            }

            executionDays[dayIndex].tasks[taskIndex].isCompleted = isCompleted
            break
        }
    }

    private func syncScheduleTaskState(
        sourceExecutionBlockID: UUID,
        sourceExecutionTaskID: UUID,
        isCompleted: Bool
    ) {
        for blockIndex in formulaBlocks.indices {
            guard let taskIndex = formulaBlocks[blockIndex].tasks.firstIndex(where: {
                $0.sourceExecutionBlockID == sourceExecutionBlockID
                    && $0.sourceExecutionTaskID == sourceExecutionTaskID
            }) else {
                continue
            }
            formulaBlocks[blockIndex].tasks[taskIndex].isCompleted = isCompleted
        }

        for blockIndex in blocks.indices {
            guard let taskIndex = blocks[blockIndex].tasks.firstIndex(where: {
                $0.sourceExecutionBlockID == sourceExecutionBlockID
                    && $0.sourceExecutionTaskID == sourceExecutionTaskID
            }) else {
                continue
            }
            blocks[blockIndex].tasks[taskIndex].isCompleted = isCompleted
        }
    }

    private func updatePlannerTask(from task: ExecutionTaskCard, plannerID: UUID) {
        let store = TasksStore.shared
        guard let index = store.tasks.firstIndex(where: { $0.id == plannerID }) else { return }

        var item = store.tasks[index]
        item.title = task.title
        item.estimatedMinutes = task.durationMinutes
        item.executionType = executionType(for: task.blockType)
        item.priority = task.isPrimary ? .high : .normal
        item.recurrence = task.isRepeating ? .daily : .none
        store.updateTask(item)
    }

    private func executionType(for blockType: BlockType) -> TaskExecutionType {
        switch blockType {
        case .focus, .fixed: return .deepWork
        case .routine: return .multitask
        case .mini: return .shallowWork
        }
    }

    private func materializedFormulaBlocks(
        formula: DayFormulaTemplate,
        anchor: Date,
        fillsFromExecution: Bool
    ) -> [DayBlock] {
        let baseBlocks = formula.materializeDay(startingAt: anchor)
        return materializedScheduleBlocks(from: baseBlocks, anchor: anchor, fillsFromExecution: fillsFromExecution)
    }

    private func materializedScheduleBlocks(
        from sourceBlocks: [DayBlock],
        anchor: Date,
        fillsFromExecution: Bool
    ) -> [DayBlock] {
        var assignedTaskIDs = Set<UUID>()

        return blocksPinnedToRunDate(sourceBlocks, runStart: anchor).map { block in
            var filledBlock = block
            filledBlock.state = .upcoming
            filledBlock.startTime = block.startTime
            filledBlock.endTime = block.endTime

            switch block.taskSource {
            case .executionFill:
                if fillsFromExecution {
                    filledBlock.tasks = makeFilledScheduleTasks(for: filledBlock, assignedTaskIDs: &assignedTaskIDs)
                } else {
                    filledBlock.tasks = block.tasks.filter { $0.sourceExecutionTaskID == nil }.map { task in
                        var resetTask = task
                        resetTask.isCompleted = false
                        return resetTask
                    }
                }
            case .templateTasks:
                filledBlock.tasks = block.tasks.map { task in
                    var resetTask = task
                    resetTask.isCompleted = false
                    return resetTask
                }
            case .noTasks:
                filledBlock.tasks = []
            }

            return filledBlock
        }
    }

    private func makeFilledScheduleTasks(
        for block: DayBlock,
        assignedTaskIDs: inout Set<UUID>
    ) -> [DayTask] {
        let manualRows = block.tasks.filter { $0.sourceExecutionTaskID == nil }
        let manualPlannerIDs = Set(manualRows.compactMap(\.plannerTaskItemID))

        let fillRule = block.fillRule ?? ScheduleFillRule()
        let candidates = (todayExecutionDay?.tasks ?? [])
            .filter { task in
                !task.isCompleted
                    && !task.isScheduleInjected
                    && !anchorClaimedCardIDs.contains(task.id)
                    && fillRule.matches(task)
                    && !assignedTaskIDs.contains(task.id)
                    && !(task.plannerTaskItemID.map { manualPlannerIDs.contains($0) } ?? false)
            }
            .sorted { lhs, rhs in
                compareAutofillCandidates(lhs, rhs, pickOrder: fillRule.pickOrder)
            }

        var selected: [ExecutionTaskCard] = []
        var usedMinutes = manualRows.reduce(0) { $0 + estimatedMinutesForManualScheduleTask($1) }

        for candidate in candidates {
            let duration = max(candidate.durationMinutes, 1)
            guard usedMinutes + duration <= block.durationMinutes else { continue }
            selected.append(candidate)
            usedMinutes += duration
            assignedTaskIDs.insert(candidate.id)
        }

        let poolRows = selected.map { card in
            DayTask(
                id: card.sourceTaskID ?? card.id,
                title: card.title,
                isCompleted: card.isCompleted,
                isPrimary: card.isPrimary,
                isRepeating: card.isRepeating,
                sourceExecutionBlockID: card.sourceBlockID,
                sourceExecutionTaskID: card.id,
                plannerTaskItemID: card.plannerTaskItemID,
                field: card.field,
                project: card.project,
                folder: card.folder
            )
        }

        return manualRows + poolRows
    }

    private func compareAutofillCandidates(
        _ lhs: ExecutionTaskCard,
        _ rhs: ExecutionTaskCard,
        pickOrder: AutofillTaskPickOrder
    ) -> Bool {
        switch pickOrder {
        case .priority:
            if lhs.isPrimary != rhs.isPrimary {
                return lhs.isPrimary && !rhs.isPrimary
            }
            let lp = autofillPlannerPriorityRank(lhs)
            let rp = autofillPlannerPriorityRank(rhs)
            if lp != rp { return lp < rp }
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        case .depthFirst:
            let ld = autofillDepthTier(lhs)
            let rd = autofillDepthTier(rhs)
            if ld != rd { return ld < rd }
            if lhs.isPrimary != rhs.isPrimary {
                return lhs.isPrimary && !rhs.isPrimary
            }
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    /// Lower = higher planner priority (packed first).
    private func autofillPlannerPriorityRank(_ card: ExecutionTaskCard) -> Int {
        guard let pid = card.plannerTaskItemID,
              let item = TasksStore.shared.tasks.first(where: { $0.id == pid })
        else {
            return 50
        }
        switch item.priority {
        case .urgent: return 0
        case .high: return 1
        case .normal: return 2
        }
    }

    /// Lower = deeper / more focus-like work (packed first).
    private func autofillDepthTier(_ card: ExecutionTaskCard) -> Int {
        let laneTier: Int
        switch card.lane {
        case .focus: laneTier = 0
        case .admin: laneTier = 1
        case .life: laneTier = 2
        }
        let typeTier: Int
        switch card.blockType {
        case .focus: typeTier = 0
        case .fixed, .mini: typeTier = 1
        case .routine: typeTier = 2
        }
        return min(laneTier, typeTier)
    }

    private func estimatedMinutesForManualScheduleTask(_ task: DayTask) -> Int {
        if let pid = task.plannerTaskItemID,
           let item = TasksStore.shared.tasks.first(where: { $0.id == pid }) {
            return max(5, item.plannedMinutes)
        }
        return 15
    }

    private static func makeExecutionDays(from blocks: [DayBlock], relativeTo now: Date) -> [ExecutionDayPlan] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        return (0...3).compactMap { dayOffset in
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { return nil }

            let cards = makeExecutionCards(
                from: blocks,
                for: day,
                usesSourceReferences: dayOffset == 0
            )
            .sorted { $0.startDate < $1.startDate }

            return ExecutionDayPlan(
                id: calendar.startOfDay(for: day),
                date: calendar.startOfDay(for: day),
                tasks: cards
            )
        }
    }

    private static func makeEmptyExecutionDays(relativeTo now: Date) -> [ExecutionDayPlan] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        return (0...3).compactMap { dayOffset in
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { return nil }
            let dayStart = calendar.startOfDay(for: day)
            return ExecutionDayPlan(id: dayStart, date: dayStart, tasks: [])
        }
    }

    private static func makeExecutionCards(
        from blocks: [DayBlock],
        for day: Date,
        usesSourceReferences: Bool
    ) -> [ExecutionTaskCard] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)

        return blocks.flatMap { block -> [ExecutionTaskCard] in
            guard !block.tasks.isEmpty else { return [] }

            let blockStart = align(block.startTime, to: dayStart, calendar: calendar)
            let blockEnd = align(block.endTime, to: dayStart, calendar: calendar)
            let blockDuration = max(Int(blockEnd.timeIntervalSince(blockStart) / 60), block.tasks.count)
            let slotMinutes = max(blockDuration / max(block.tasks.count, 1), 1)

            return block.tasks.enumerated().map { taskOffset, task in
                let start = calendar.date(
                    byAdding: .minute,
                    value: slotMinutes * taskOffset,
                    to: blockStart
                ) ?? blockStart
                let remaining = max(Int(blockEnd.timeIntervalSince(start) / 60), 1)
                let duration = taskOffset == block.tasks.count - 1 ? remaining : max(slotMinutes, 1)

                return ExecutionTaskCard(
                    id: usesSourceReferences ? task.id : UUID(),
                    sourceBlockID: usesSourceReferences ? block.id : nil,
                    sourceTaskID: usesSourceReferences ? task.id : nil,
                    title: task.title,
                    blockTitle: block.title,
                    blockTypeLabel: block.type.label,
                    blockType: block.type,
                    startDate: start,
                    durationMinutes: duration,
                    lane: ExecutionLane.suggested(for: block.type),
                    isCompleted: usesSourceReferences ? task.isCompleted : false,
                    isRepeating: task.isRepeating,
                    isPrimary: task.isPrimary,
                    field: task.field,
                    project: task.project,
                    folder: task.folder,
                    plannerTaskItemID: nil,
                    pinsToClock: block.pinsToClock,
                    timelineAccentHex: block.timelineAccentHex
                )
            }
        }
    }

    private static func align(_ date: Date, to day: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: 0,
            of: day
        ) ?? day
    }

    private var calendar: Calendar { Calendar.current }

    private func minimumMovableStart(for dayID: Date) -> Date? {
        calendar.isDate(dayID, inSameDayAs: currentTime) ? currentTime : nil
    }
}
