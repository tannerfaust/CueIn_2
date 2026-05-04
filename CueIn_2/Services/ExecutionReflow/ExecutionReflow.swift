import Foundation

// MARK: - ExecutionReflow
/// Strategy for reshaping a day's scheduled task list when one task is moved,
/// resized, or dropped. The Today/Execution timeline calls into this seam every
/// time the user drags a card. A future AI reflow implementation plugs in here
/// without the view knowing which strategy is running.
///
/// Principles (per docs/Rules_and_Architecture.md):
/// • AI is an enhancement layer, not the foundation → the default is deterministic.
/// • AI must always have a fallback behavior → this protocol *is* the fallback surface.
/// • Useful AI only → the AI variant proposes, the same protocol applies the result.

protocol ExecutionReflow {
    /// Given the current task list on a day and a proposed change, return a new
    /// task list with start times resolved (snapping, collision resolution, fixed
    /// anchors respected). Durations are preserved.
    func reflow(
        tasks: [ExecutionTaskCard],
        change: ExecutionReflowChange,
        dayStart: Date,
        calendar: Calendar
    ) -> [ExecutionTaskCard]
}

// MARK: - ExecutionReflowChange

/// A single user-intent change that the reflow must accommodate.
enum ExecutionReflowChange {
    /// Move a task's start time. Duration is preserved.
    case move(taskID: UUID, proposedStart: Date, minimumMovableStart: Date?)

    /// Reorder the tasks that belong to the same source block, repacking start
    /// times sequentially from the block's current window start.
    case reorderWithinBlock(sourceBlockID: UUID, orderedTaskIDs: [UUID])
}

// MARK: - AdaptiveExecutionReflow
/// Deterministic Motion-style planner for the execution calendar.
///
/// The model is intentionally AI-ready but not AI-dependent:
/// - Fixed and completed tasks are calendar anchors.
/// - The user-dragged task becomes a temporary reservation.
/// - Remaining movable tasks are packed into the open windows around anchors.
/// - The same function is used for drag previews and final drops, so the user
///   sees the real schedule while dragging instead of a cosmetic placeholder.
///
/// Snapping: all proposed start times snap to `snapMinutes` (default 5).

struct AdaptiveExecutionReflow: ExecutionReflow {

    let snapMinutes: Int

    init(snapMinutes: Int = 5) {
        self.snapMinutes = snapMinutes
    }

    func reflow(
        tasks: [ExecutionTaskCard],
        change: ExecutionReflowChange,
        dayStart: Date,
        calendar: Calendar
    ) -> [ExecutionTaskCard] {
        switch change {
        case let .move(taskID, proposedStart, minimumMovableStart):
            return applyMove(
                tasks: tasks,
                taskID: taskID,
                proposedStart: proposedStart,
                minimumMovableStart: minimumMovableStart,
                dayStart: dayStart,
                calendar: calendar
            )

        case let .reorderWithinBlock(sourceBlockID, orderedTaskIDs):
            return applyReorderWithinBlock(tasks: tasks, sourceBlockID: sourceBlockID, orderedTaskIDs: orderedTaskIDs, calendar: calendar)
        }
    }

    // MARK: Move with adaptive packing

    private func applyMove(
        tasks: [ExecutionTaskCard],
        taskID: UUID,
        proposedStart: Date,
        minimumMovableStart: Date?,
        dayStart: Date,
        calendar: Calendar
    ) -> [ExecutionTaskCard] {
        guard let movingTask = tasks.first(where: { $0.id == taskID }) else { return tasks }
        guard !movingTask.pinsToClock, !movingTask.isCompleted else { return tasks }

        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let movableStart = max(dayStart, minimumMovableStart ?? dayStart)
        let duration = max(movingTask.durationMinutes, 1)

        let snapped = snap(proposedStart, dayStart: dayStart, calendar: calendar)
        let fixedReservations = reservations(
            from: tasks,
            excluding: taskID,
            where: { $0.pinsToClock || $0.isCompleted || $0.startDate < movableStart }
        )
        let resolvedStart = nearestAvailableStart(
            desiredStart: snapped,
            durationMinutes: duration,
            reservations: fixedReservations,
            dayStart: movableStart,
            dayEnd: dayEnd,
            calendar: calendar
        )

        var resultByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        resultByID[taskID]?.startDate = resolvedStart

        let movingReservation = Reservation(
            id: taskID,
            start: resolvedStart,
            end: calendar.date(byAdding: .minute, value: duration, to: resolvedStart) ?? resolvedStart
        )
        let anchored = fixedReservations + [movingReservation]
        let movable = tasks
            .filter { $0.id != taskID && !$0.pinsToClock && !$0.isCompleted }
            .filter { $0.startDate >= movableStart }
            .sorted(by: planningOrder)

        let placements = pack(
            movableTasks: movable,
            around: anchored,
            dayStart: movableStart,
            dayEnd: dayEnd,
            calendar: calendar
        )

        for (id, start) in placements {
            resultByID[id]?.startDate = start
        }

        return tasks.compactMap { resultByID[$0.id] }.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            return planningOrder(lhs, rhs)
        }
    }

    // MARK: Reorder within block

    private func applyReorderWithinBlock(
        tasks: [ExecutionTaskCard],
        sourceBlockID: UUID,
        orderedTaskIDs: [UUID],
        calendar: Calendar
    ) -> [ExecutionTaskCard] {
        var result = tasks
        let blockTasks = result.filter { $0.sourceBlockID == sourceBlockID }
        guard let windowStart = blockTasks.map(\.startDate).min() else { return tasks }

        var cursor = windowStart
        var updates: [UUID: Date] = [:]
        for id in orderedTaskIDs {
            guard let task = blockTasks.first(where: { $0.id == id }) else { continue }
            updates[id] = cursor
            cursor = calendar.date(byAdding: .minute, value: max(task.durationMinutes, 1), to: cursor) ?? cursor
        }

        for i in result.indices {
            if let newStart = updates[result[i].id] {
                result[i].startDate = newStart
            }
        }
        result.sort { $0.startDate < $1.startDate }
        return result
    }

    // MARK: Packing

    private struct Reservation {
        let id: UUID
        let start: Date
        let end: Date
    }

    private struct OpenWindow {
        let start: Date
        let end: Date

        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    private func reservations(
        from tasks: [ExecutionTaskCard],
        excluding excludedID: UUID?,
        where isReserved: (ExecutionTaskCard) -> Bool
    ) -> [Reservation] {
        tasks
            .filter { $0.id != excludedID && isReserved($0) }
            .map { Reservation(id: $0.id, start: $0.startDate, end: $0.endDate) }
            .sorted { $0.start < $1.start }
    }

    private func nearestAvailableStart(
        desiredStart: Date,
        durationMinutes: Int,
        reservations: [Reservation],
        dayStart: Date,
        dayEnd: Date,
        calendar: Calendar
    ) -> Date {
        let duration = TimeInterval(durationMinutes * 60)
        let windows = openWindows(
            dayStart: dayStart,
            dayEnd: dayEnd,
            reservations: reservations
        )
        guard !windows.isEmpty else { return dayStart }

        let candidates = windows.compactMap { window -> Date? in
            guard window.duration >= duration else { return nil }
            let latest = window.end.addingTimeInterval(-duration)
            return min(max(desiredStart, window.start), latest)
        }
        guard let best = candidates.min(by: { abs($0.timeIntervalSince(desiredStart)) < abs($1.timeIntervalSince(desiredStart)) }) else {
            return windows.min(by: { abs($0.start.timeIntervalSince(desiredStart)) < abs($1.start.timeIntervalSince(desiredStart)) })?.start ?? dayStart
        }

        return snap(best, dayStart: dayStart, calendar: calendar)
    }

    private func pack(
        movableTasks: [ExecutionTaskCard],
        around reservations: [Reservation],
        dayStart: Date,
        dayEnd: Date,
        calendar: Calendar
    ) -> [UUID: Date] {
        let windows = openWindows(
            dayStart: dayStart,
            dayEnd: dayEnd,
            reservations: reservations
        )
        guard !windows.isEmpty else { return [:] }

        var placements: [UUID: Date] = [:]
        var windowIndex = 0
        var cursor = windows[0].start

        for task in movableTasks {
            let durationMinutes = max(task.durationMinutes, 1)
            let duration = TimeInterval(durationMinutes * 60)

            while windowIndex < windows.count {
                let window = windows[windowIndex]
                cursor = max(cursor, window.start)
                let proposedEnd = cursor.addingTimeInterval(duration)
                if proposedEnd <= window.end {
                    placements[task.id] = cursor
                    cursor = proposedEnd
                    break
                }

                windowIndex += 1
                if windowIndex < windows.count {
                    cursor = windows[windowIndex].start
                }
            }
        }

        return placements
    }

    private func openWindows(
        dayStart: Date,
        dayEnd: Date,
        reservations: [Reservation]
    ) -> [OpenWindow] {
        var windows: [OpenWindow] = []
        var cursor = dayStart

        for reservation in reservations.sorted(by: { $0.start < $1.start }) {
            let start = max(reservation.start, dayStart)
            let end = min(reservation.end, dayEnd)
            guard end > dayStart, start < dayEnd else { continue }

            if start > cursor {
                windows.append(OpenWindow(start: cursor, end: start))
            }
            cursor = max(cursor, end)
        }

        if cursor < dayEnd {
            windows.append(OpenWindow(start: cursor, end: dayEnd))
        }

        return windows.filter { $0.end > $0.start }
    }

    private func planningOrder(_ lhs: ExecutionTaskCard, _ rhs: ExecutionTaskCard) -> Bool {
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }
        if lhs.isPrimary != rhs.isPrimary {
            return lhs.isPrimary && !rhs.isPrimary
        }
        if lhs.isRepeating != rhs.isRepeating {
            return lhs.isRepeating && !rhs.isRepeating
        }
        if lhs.blockType != rhs.blockType {
            return blockTypeRank(lhs.blockType) < blockTypeRank(rhs.blockType)
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func blockTypeRank(_ blockType: BlockType) -> Int {
        switch blockType {
        case .focus: return 0
        case .routine: return 1
        case .mini: return 2
        case .fixed: return 3
        }
    }

    // MARK: Snap

    private func snap(_ date: Date, dayStart: Date, calendar: Calendar) -> Date {
        let minutes = calendar.dateComponents([.minute], from: dayStart, to: date).minute ?? 0
        let snapped = Int((Double(minutes) / Double(snapMinutes)).rounded()) * snapMinutes
        return calendar.date(byAdding: .minute, value: snapped, to: dayStart) ?? date
    }
}

typealias CascadeReflow = AdaptiveExecutionReflow
