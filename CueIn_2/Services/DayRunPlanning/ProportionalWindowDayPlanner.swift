import Foundation

// MARK: - ProportionalWindowDayPlanner

/// Distributes `[runStart, targetEnd]` across planned blocks **in proportion to nominal minutes**.
/// Tasks stay attached to their blocks; only `startTime` / `endTime` change.
///
/// Blocks with ``DayBlock/locksPlannedDuration`` reserve their nominal slice first (scaled only if
/// the window cannot fit all locked nominals); remaining time is split proportionally among flexible blocks.
///
/// - If nominals are missing for an id, falls back to the block’s current ``DayBlock/durationMinutes``.
/// - Last planned block ends exactly at ``DayRunPlanContext/targetEnd`` so the chosen “day end” is honored.

struct ProportionalWindowDayPlanner: DayRunPlanning {

    func makePlan(context: DayRunPlanContext) throws -> DayRunPlanResult {
        guard context.targetEnd > context.runStart else { throw DayRunPlanningError.targetEndNotAfterRunStart }
        guard !context.plannedBlockIndices.isEmpty else { throw DayRunPlanningError.emptyPlan }

        let n = context.blocks.count
        for idx in context.plannedBlockIndices {
            guard idx >= 0 && idx < n else { throw DayRunPlanningError.invalidBlockIndex(idx) }
        }

        var out = context.blocks
        let windowSeconds = context.targetEnd.timeIntervalSince(context.runStart)
        guard windowSeconds > 0 else { throw DayRunPlanningError.targetEndNotAfterRunStart }

        let windowMinutes = windowSeconds / 60

        struct Slice {
            let blockIndex: Int
            let nominal: Double
            let locked: Bool
        }

        let slices: [Slice] = context.plannedBlockIndices.map { blockIndex in
            let block = out[blockIndex]
            let id = block.id
            let nominal = Double(context.nominalMinutesByBlockID[id] ?? max(block.durationMinutes, 1))
            return Slice(blockIndex: blockIndex, nominal: max(nominal, 1), locked: block.locksPlannedDuration)
        }

        let lockedSlices = slices.filter(\.locked)
        let flexSlices = slices.filter { !$0.locked }

        let totalLockedNominal = lockedSlices.reduce(0.0) { $0 + $1.nominal }
        let totalFlexNominal = flexSlices.reduce(0.0) { $0 + $1.nominal }

        var allocatedByIndex: [Int: Double] = [:]

        // Locked blocks share the window first (uniform scale if necessary).
        if !lockedSlices.isEmpty {
            let scale = totalLockedNominal > windowMinutes ? windowMinutes / totalLockedNominal : 1
            for s in lockedSlices {
                allocatedByIndex[s.blockIndex] = s.nominal * scale
            }
        }

        let usedByLocked = lockedSlices.reduce(0.0) { partial, s in
            partial + (allocatedByIndex[s.blockIndex] ?? 0)
        }
        let remainingForFlex = max(0, windowMinutes - usedByLocked)

        if !flexSlices.isEmpty {
            if totalFlexNominal <= 0 {
                for s in flexSlices {
                    allocatedByIndex[s.blockIndex] = 0
                }
            } else {
                let scaleFlex = remainingForFlex / totalFlexNominal
                for s in flexSlices {
                    allocatedByIndex[s.blockIndex] = s.nominal * scaleFlex
                }
            }
        }

        var cursor = context.runStart
        for (ord, s) in slices.enumerated() {
            let minutes = allocatedByIndex[s.blockIndex] ?? s.nominal
            let isLast = ord == slices.count - 1
            let end: Date
            if isLast {
                end = context.targetEnd
            } else {
                let secs = minutes * 60
                end = cursor.addingTimeInterval(secs)
            }
            let bi = s.blockIndex
            out[bi].startTime = cursor
            out[bi].endTime = end
            cursor = end
        }

        let totalNominalMinutes = slices.reduce(0.0) { $0 + $1.nominal }

        let metadata = DayRunPlanMetadata(
            planningSource: context.planningSource,
            windowDuration: windowSeconds,
            totalNominalMinutes: totalNominalMinutes
        )
        return DayRunPlanResult(blocks: out, metadata: metadata)
    }
}
